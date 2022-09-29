pragma solidity ^0.8.13;

import "../interfaces/IERC20.sol";
import {IRouter} from "../interfaces/velo/IRouter.sol";
import {IGauge} from "../interfaces/velo/IGauge.sol";
import {IL2ERC20Bridge} from "../interfaces/velo/IL2ERC20Bridge.sol";
import {ICrossDomainMessenger} from "../interfaces/velo/ICrossDomainMessenger.sol";

contract VeloFarmer {
    address public chair;
    address public l2chair;
    address public gov;
    address public treasury;
    uint public maxSlippageBpsDolaToUsdc;
    uint public maxSlippageBpsUsdcToDola;
    uint public maxSlippageBpsLiquidity;

    uint public constant DOLA_USDC_CONVERSION_MULTI= 1e12;
    uint public constant PRECISION = 10_000;

    IRouter public immutable router;
    IGauge public immutable dolaGauge = IGauge(0xAFD2c84b9d1cd50E7E18a55e419749A6c9055E1F);
    IERC20 public immutable DOLA;
    IERC20 public immutable USDC;
    IERC20 public immutable LP_TOKEN = IERC20(0x6C5019D345Ec05004A7E7B0623A91a0D9B8D590d);
    address public immutable veloTokenAddr = 0x3c8B650257cFb5f272f799F5e2b4e65093a11a05;
    ICrossDomainMessenger public immutable ovmL2CrossDomainMessenger = ICrossDomainMessenger(0x4200000000000000000000000000000000000007);
    IL2ERC20Bridge public immutable bridge;
    address public optiFed;

    error OnlyChair();
    error OnlyGov();
    error MaxSlippageTooHigh();
    error NotEnoughTokens();
    
    constructor(
            address payable routerAddr_, 
            address dolaAddr_, 
            address usdcAddr_,
            address gov_,
            address treasury_,
            address bridge_,
            address optiFed_
        )
    {
        router = IRouter(routerAddr_);
        DOLA = IERC20(dolaAddr_);
        USDC = IERC20(usdcAddr_);
        chair = msg.sender;
        gov = gov_;
        treasury = treasury_;
        bridge = IL2ERC20Bridge(bridge_);
        optiFed = optiFed_;
        
        DOLA.approve(routerAddr_, type(uint256).max);
        USDC.approve(routerAddr_, type(uint256).max);
        LP_TOKEN.approve(address(dolaGauge), type(uint).max);
        LP_TOKEN.approve(address(router), type(uint).max);
    }

    modifier onlyGov() {
        if (msg.sender != address(ovmL2CrossDomainMessenger) ||
            ovmL2CrossDomainMessenger.xDomainMessageSender() != gov
        ) revert OnlyGov();
        _;
    }

    modifier onlyChair() {
        if ((msg.sender != address(ovmL2CrossDomainMessenger) ||
            ovmL2CrossDomainMessenger.xDomainMessageSender() != chair) &&
            msg.sender != l2chair
        ) revert OnlyChair();
        _;
    }

    /**
    @notice Claims all VELO token rewards accrued by this contract & transfer all VELO owned by this contract to `treasury`
    */
    function claimVeloRewards() external {
        address[] memory addr = new address[](1);
        addr[0] = veloTokenAddr;
        dolaGauge.getReward(address(this), addr);

        IERC20(addr[0]).transfer(treasury, IERC20(addr[0]).balanceOf(address(this)));
    }

    /**
    @notice Attempts to claim token rewards & transfer all reward tokens owned by this contract to `treasury`
    @param addrs Array of token addresses to claim rewards of.
    */
    function claimRewards(address[] calldata addrs) external onlyChair {
        dolaGauge.getReward(address(this), addrs);

        for (uint i = 0; i < addrs.length; i++) {
            IERC20(addrs[i]).transfer(treasury, IERC20(addrs[i]).balanceOf(address(this)));
        }
    }

    /**
    @notice Swaps half of `dolaAmount` into USDC through Velodrome. Adds liquidity to DOLA/USDC pool, then deposits LP tokens into DOLA gauge.
    @param dolaAmount Amount of DOLA used. Half will be swapped to USDC, other half will be supplied as liquidity with the USDC.
    */
    function swapAndDeposit(uint dolaAmount) external onlyChair {
        uint halfDolaAmount = dolaAmount / 2;
        uint minOut = halfDolaAmount * (PRECISION - maxSlippageBpsDolaToUsdc) / PRECISION / DOLA_USDC_CONVERSION_MULTI;
        uint[] memory amounts = router.swapExactTokensForTokensSimple(halfDolaAmount, minOut, address(DOLA), address(USDC), true, address(this), block.timestamp);

        uint dolaAmountMin = halfDolaAmount * (PRECISION - maxSlippageBpsLiquidity) / PRECISION;
        uint usdcAmountMin = dolaAmountMin / DOLA_USDC_CONVERSION_MULTI;

        router.addLiquidity(address(DOLA), address(USDC), true, halfDolaAmount, amounts[amounts.length - 1], dolaAmountMin, usdcAmountMin, address(this), block.timestamp);
        dolaGauge.deposit(LP_TOKEN.balanceOf(address(this)), 0);
    }

    /**
    @notice Attempts to deposit `dolaAmount` of DOLA & `usdcAmount` of USDC into Velodrome DOLA/USDC stable pool. Then, deposits LP tokens into gauge.
    @param dolaAmount Amount of DOLA to be added as liquidity in Velodrome DOLA/USDC pool
    @param usdcAmount Amount of USDC to be added as liquidity in Velodrome DOLA/USDC pool
    */
    function deposit(uint dolaAmount, uint usdcAmount) public onlyChair {
        uint dolaAmountMin = dolaAmount * (PRECISION - maxSlippageBpsLiquidity) / PRECISION;
        uint usdcAmountMin = usdcAmount * (PRECISION - maxSlippageBpsLiquidity) / PRECISION;

        router.addLiquidity(address(DOLA), address(USDC), true, dolaAmount, usdcAmount, dolaAmountMin, usdcAmountMin, address(this), block.timestamp);
        dolaGauge.deposit(LP_TOKEN.balanceOf(address(this)), 0);
    }

    /**
    @notice Calls `deposit()` with entire DOLA & USDC token balance of this contract.
    */
    function depositAll() external {
        deposit(DOLA.balanceOf(address(this)), USDC.balanceOf(address(this)));
    }

    /**
    @notice Withdraws `dolaAmount` worth of LP tokens from gauge. Then, redeems LP tokens for DOLA/USDC.
    @param dolaAmount Desired dola value to remove from DOLA/USDC pool. Will attempt to remove 50/50 while allowing for `maxSlippageBpsLiquidity` bps of variance.
    @return Amount of USDC received from liquidity removal. Used by withdrawLiquidityAndSwap wrapper.
    */
    function withdrawLiquidity(uint dolaAmount) public onlyChair returns (uint) {
        uint liquidity = dolaGauge.balanceOf(address(this));
        (uint dolaAmountOut, ) = router.quoteRemoveLiquidity(address(DOLA), address(USDC), true, liquidity);
        uint withdrawAmount = (dolaAmount / 2) * liquidity / dolaAmountOut;
        if (withdrawAmount > liquidity) withdrawAmount = liquidity;

        dolaGauge.withdraw(withdrawAmount);

        uint dolaAmountMin = dolaAmount / 2 * (PRECISION - maxSlippageBpsLiquidity) / PRECISION;
        uint usdcAmountMin = dolaAmountMin / DOLA_USDC_CONVERSION_MULTI;

        (, uint amountUSDC) = router.removeLiquidity(address(DOLA), address(USDC), true, withdrawAmount, dolaAmountMin, usdcAmountMin, address(this), block.timestamp);
        return amountUSDC;
    }

    /**
    @notice Withdraws `dolaAmount` worth of LP tokens from gauge. Then, redeems LP tokens for DOLA/USDC and swaps redeemed USDC to DOLA.
    @param dolaAmount Desired dola value to remove from DOLA/USDC pool. Will attempt to remove 50/50 while allowing for `maxSlippageBpsLiquidity` bps of variance.
    */
    function withdrawLiquidityAndSwapToDOLA(uint dolaAmount) external {
        uint usdcAmount = withdrawLiquidity(dolaAmount);

        swapUSDCtoDOLA(usdcAmount);
    }

    /**
    @notice Withdraws `dolaAmount` of DOLA to optiFed on L1. Will take 7 days before withdraw is claimable on L1.
    @param dolaAmount Amount of DOLA to withdraw and send to L1 OptiFed
    */
    function withdrawToL1OptiFed(uint dolaAmount) external onlyChair {
        if (dolaAmount > DOLA.balanceOf(address(this))) revert NotEnoughTokens();

        bridge.withdrawTo(address(DOLA), optiFed, dolaAmount, 0, "");
    }

    /**
    @notice Withdraws `dolaAmount` of DOLA & `usdcAmount` of USDC to optiFed on L1. Will take 7 days before withdraw is claimable on L1.
    @param dolaAmount Amount of DOLA to withdraw and send to L1 OptiFed
    @param usdcAmount Amount of USDC to withdraw and send to L1 OptiFed
    */
    function withdrawToL1OptiFed(uint dolaAmount, uint usdcAmount) external onlyChair {
        if (dolaAmount > DOLA.balanceOf(address(this))) revert NotEnoughTokens();
        if (usdcAmount > USDC.balanceOf(address(this))) revert NotEnoughTokens();

        bridge.withdrawTo(address(DOLA), optiFed, dolaAmount, 0, "");
        bridge.withdrawTo(address(USDC), optiFed, usdcAmount, 0, "");
    }

    /**
    @notice Withdraws `amount` of `l2Token` to address `to` on L1. Will take 7 days before withdraw is claimable.
    @param l2Token Address of the L2 token to be withdrawn
    @param to L1 Address that tokens will be sent to
    @param amount Amount of the L2 token to be withdrawn
    */
    function withdrawTokensToL1(address l2Token, address to, uint amount) external onlyChair {
        if (amount > IERC20(l2Token).balanceOf(address(this))) revert NotEnoughTokens();

        IERC20(l2Token).approve(address(bridge), amount);
        bridge.withdrawTo(address(l2Token), to, amount, 0, "");
    }

    /**
    @notice Swap `usdcAmount` of USDC to DOLA through velodrome.
    @param usdcAmount Amount of USDC to swap to DOLA
    */
    function swapUSDCtoDOLA(uint usdcAmount) public onlyChair {
        uint minOut = usdcAmount * (PRECISION - maxSlippageBpsUsdcToDola) / PRECISION * DOLA_USDC_CONVERSION_MULTI;
        router.swapExactTokensForTokensSimple(usdcAmount, minOut, address(USDC), address(DOLA), true, address(this), block.timestamp);
    }

    /**
    @notice Swap `dolaAmount` of DOLA to USDC through velodrome.
    @param dolaAmount Amount of DOLA to swap to USDC
    */
    function swapDOLAtoUSDC(uint dolaAmount) public onlyChair { 
        uint minOut = dolaAmount * (PRECISION - maxSlippageBpsDolaToUsdc) / PRECISION / DOLA_USDC_CONVERSION_MULTI;
        router.swapExactTokensForTokensSimple(dolaAmount, minOut, address(DOLA), address(USDC), true, address(this), block.timestamp);
    }

    /**
    @notice Method for current chair of the fed to resign
    */
    function resign() external onlyChair {
        if (msg.sender == l2chair) {
            l2chair = address(0);
        } else {
            chair = address(0);
        }
    }

    /**
    @notice Governance only function for setting acceptable slippage when swapping DOLA -> USDC
    @param newMaxSlippageBps The new maximum allowed loss for DOLA -> USDC swaps. 1 = 0.01%
    */
    function setMaxSlippageDolaToUsdc(uint newMaxSlippageBps) onlyGov external {
        if (newMaxSlippageBps > 10000) revert MaxSlippageTooHigh();
        maxSlippageBpsDolaToUsdc = newMaxSlippageBps;
    }

    /**
    @notice Governance only function for setting acceptable slippage when swapping USDC -> DOLA
    @param newMaxSlippageBps The new maximum allowed loss for USDC -> DOLA swaps. 1 = 0.01%
    */
    function setMaxSlippageUsdcToDola(uint newMaxSlippageBps) onlyGov external {
        if (newMaxSlippageBps > 10000) revert MaxSlippageTooHigh();
        maxSlippageBpsUsdcToDola = newMaxSlippageBps;
    }

    /**
    @notice Governance only function for setting acceptable slippage when adding or removing liquidty from DOLA/USDC pool
    @param newMaxSlippageBps The new maximum allowed loss for adding/removing liquidity from DOLA/USDC pool. 1 = 0.01%
    */
    function setMaxSlippageLiquidity(uint newMaxSlippageBps) onlyGov external {
        if (newMaxSlippageBps > 10000) revert MaxSlippageTooHigh();
        maxSlippageBpsLiquidity = newMaxSlippageBps;
    }

    /**
    @notice Method for gov to change gov address
    @dev gov address should be set to the address of L1 VeloFarmerMessenger if it is being used
    @param newGov_ L1 address to be set as gov
    */
    function changeGov(address newGov_) external onlyGov {
        gov = newGov_;
    }

    /**
    @notice Method for gov to change treasury address, the address that receives all rewards
    @param newTreasury_ L2 address to be set as treasury
    */
    function changeTreasury(address newTreasury_) external onlyGov {
        treasury = newTreasury_;
    }

    /**
    @notice Method for gov to change the chair
    @dev chair address should be set to the address of L1 VeloFarmerMessenger if it is being used
    @param newChair_ L1 address to be set as chair
    */
    function changeChair(address newChair_) external onlyGov {
        chair = newChair_;
    }

    /**
    @notice Method for gov to change the L2 chair
    @param newL2Chair_ L2 address to be set as l2chair
    */
    function changeL2Chair(address newL2Chair_) external onlyGov {
        l2chair = newL2Chair_;
    }

    /**
    @notice Method for gov to change the L1 optiFed address
    @dev optiFed is the L1 address that receives all bridged DOLA/USDC from both withdrawToL1OptiFed functions
    @param newOptiFed_ L1 address to be set as optiFed
    */
    function changeOptiFed(address newOptiFed_) external onlyGov {
        optiFed = newOptiFed_;
    }
}