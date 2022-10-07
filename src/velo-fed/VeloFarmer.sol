pragma solidity ^0.8.13;

import "../interfaces/IERC20.sol";
import {IRouter} from "../interfaces/velo/IRouter.sol";
import {IGauge} from "../interfaces/velo/IGauge.sol";
import {IL2ERC20Bridge} from "../interfaces/velo/IL2ERC20Bridge.sol";
import {ICrossDomainMessenger} from "../interfaces/velo/ICrossDomainMessenger.sol";

contract VeloFarmer {
    address public chair;
    address public l2chair;
    address public pendingGov;
    address public gov;
    address public treasury;
    address public guardian;
    uint public maxSlippageBpsDolaToUsdc;
    uint public maxSlippageBpsUsdcToDola;
    uint public maxSlippageBpsLiquidity;

    uint public constant DOLA_USDC_CONVERSION_MULTI= 1e12;
    uint public constant PRECISION = 10_000;

    IGauge public constant dolaGauge = IGauge(0xAFD2c84b9d1cd50E7E18a55e419749A6c9055E1F);
    IERC20 public constant LP_TOKEN = IERC20(0x6C5019D345Ec05004A7E7B0623A91a0D9B8D590d);
    address public constant veloTokenAddr = 0x3c8B650257cFb5f272f799F5e2b4e65093a11a05;
    ICrossDomainMessenger public constant ovmL2CrossDomainMessenger = ICrossDomainMessenger(0x4200000000000000000000000000000000000007);
    IRouter public router;
    IERC20 public DOLA;
    IERC20 public USDC;
    IL2ERC20Bridge public bridge;
    address public optiFed;

    error OnlyChair();
    error OnlyGov();
    error OnlyPendingGov();
    error OnlyGovOrGuardian();
    error MaxSlippageTooHigh();
    error NotEnoughTokens();
    error LiquiditySlippageTooHigh();
    
    constructor(
            address payable routerAddr_, 
            address dolaAddr_, 
            address usdcAddr_,
            address gov_,
            address chair_,
            address treasury_,
            address guardian_,
            address bridge_,
            address optiFed_,
            uint maxSlippageBpsDolaToUsdc_,
            uint maxSlippageBpsUsdcToDola_,
            uint maxSlippageBpsLiquidity_
        )
    {
        router = IRouter(routerAddr_);
        DOLA = IERC20(dolaAddr_);
        USDC = IERC20(usdcAddr_);
        chair = chair_;
        gov = gov_;
        treasury = treasury_;
        guardian = guardian_;
        bridge = IL2ERC20Bridge(bridge_);
        optiFed = optiFed_;
        maxSlippageBpsDolaToUsdc = maxSlippageBpsDolaToUsdc_;
        maxSlippageBpsUsdcToDola = maxSlippageBpsUsdcToDola_;
        maxSlippageBpsLiquidity = maxSlippageBpsLiquidity_;
    }

    modifier onlyGov() {
        if (msg.sender != address(ovmL2CrossDomainMessenger) ||
            ovmL2CrossDomainMessenger.xDomainMessageSender() != gov
        ) revert OnlyGov();
        _;
    }

    modifier onlyPendingGov() {
        if (msg.sender != address(ovmL2CrossDomainMessenger) ||
            ovmL2CrossDomainMessenger.xDomainMessageSender() != pendingGov
        ) revert OnlyPendingGov();
        _;
    }

    modifier onlyChair() {
        if ((msg.sender != address(ovmL2CrossDomainMessenger) ||
            ovmL2CrossDomainMessenger.xDomainMessageSender() != chair) &&
            msg.sender != l2chair
        ) revert OnlyChair();
        _;
    }

    modifier onlyGovOrGuardian() {
        if ((msg.sender != address(ovmL2CrossDomainMessenger) ||
            (ovmL2CrossDomainMessenger.xDomainMessageSender() != gov) &&
             ovmL2CrossDomainMessenger.xDomainMessageSender() != guardian)
        ) revert OnlyGovOrGuardian();
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
    @notice Swaps the majority token for the minority token in the DOLA/USDC Velodrome pool, and then adds liquidity to DOLA/USDC pool, then deposits LP tokens into DOLA gauge.
    @dev The optimizeLP function is not precise, and will likely leave some dust amount of tokens in the contract.
    @param dolaAmount Amount of DOLA to be used. Some may be sold for USDC if there's an excess of DOLA in the pair.
    @param usdcAmount Amount of USDC to be used. Some may be sold for DOLA if there's an excess of USDC in the pair.
    */
    function swapAndDeposit(uint dolaAmount, uint usdcAmount) public onlyChair {
        address pair = router.pairFor(address(DOLA), address(USDC), true);
        uint dolaToDeposit;
        uint usdcToDeposit;
        //1e12 magic number is to adjust for USDC 6 decimals precision
        (uint dolaForUsdc, uint usdcForDola) = optimizeLP(DOLA.balanceOf(pair), USDC.balanceOf(pair)*1e12, dolaAmount, usdcAmount*1e12);
        usdcForDola = usdcForDola / 1e12;
        if(usdcForDola == 0){
            uint minOut = dolaForUsdc * (PRECISION - maxSlippageBpsDolaToUsdc) / PRECISION / DOLA_USDC_CONVERSION_MULTI;
            DOLA.approve(address(router), dolaForUsdc);
            uint[] memory amounts = router.swapExactTokensForTokensSimple(dolaForUsdc, minOut, address(DOLA), address(USDC), true, address(this), block.timestamp);
            dolaToDeposit = dolaAmount - dolaForUsdc;
            usdcToDeposit = usdcAmount + amounts[1];
        } else {
            uint minOut = usdcForDola * (PRECISION - maxSlippageBpsDolaToUsdc) / PRECISION * DOLA_USDC_CONVERSION_MULTI;
            USDC.approve(address(router), usdcForDola);
            uint[] memory amounts = router.swapExactTokensForTokensSimple(usdcForDola, minOut, address(USDC), address(DOLA), true, address(this), block.timestamp);       
            dolaToDeposit = dolaAmount + amounts[1];
            usdcToDeposit = usdcAmount - usdcForDola;
        }
        USDC.approve(address(router), usdcToDeposit);
        DOLA.approve(address(router), dolaToDeposit);
        deposit(dolaToDeposit, usdcToDeposit);
    }
    /**
    @notice Attemps to add all tokens in the Fed as liquidity before depositing to the DOLA gauge. It is likely that some dust amount will be left.
    */
    function swapAndDepositAll() public onlyChair {
        swapAndDeposit(DOLA.balanceOf(address(this)), USDC.balanceOf(address(this)));
    }

    /**
    @notice Attempts to deposit `dolaAmount` of DOLA & `usdcAmount` of USDC into Velodrome DOLA/USDC stable pool. Then, deposits LP tokens into gauge.
    @param dolaAmount Amount of DOLA to be added as liquidity in Velodrome DOLA/USDC pool
    @param usdcAmount Amount of USDC to be added as liquidity in Velodrome DOLA/USDC pool
    */
    function deposit(uint dolaAmount, uint usdcAmount) public onlyChair {
        uint lpTokenPrice = getLpTokenPrice(false);

        DOLA.approve(address(router), dolaAmount);
        USDC.approve(address(router), usdcAmount);
        (uint dolaSpent, uint usdcSpent, uint lpTokensReceived) = router.addLiquidity(address(DOLA), address(USDC), true, dolaAmount, usdcAmount, 0, 0, address(this), block.timestamp);

        (uint usdcDolaValue,) = router.getAmountOut(usdcSpent, address(USDC), address(DOLA));
        uint totalDolaValue = dolaSpent + usdcDolaValue;

        uint expectedLpTokens = totalDolaValue * 1e18 / lpTokenPrice * (PRECISION - maxSlippageBpsLiquidity) / PRECISION;
        if (lpTokensReceived < expectedLpTokens) revert LiquiditySlippageTooHigh();
        
        LP_TOKEN.approve(address(dolaGauge), LP_TOKEN.balanceOf(address(this)));
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
    @dev If attempting to remove more DOLA than total LP tokens are worth, will remove all LP tokens.
    @param dolaAmount Desired dola value to remove from DOLA/USDC pool. Will attempt to remove 50/50 while allowing for `maxSlippageBpsLiquidity` bps of variance.
    @return Amount of USDC received from liquidity removal. Used by withdrawLiquidityAndSwap wrapper.
    */
    function withdrawLiquidity(uint dolaAmount) public onlyChair returns (uint) {
        uint lpTokenPrice = getLpTokenPrice(true);
        uint liquidityToWithdraw = dolaAmount * 1e18 / lpTokenPrice;
        uint ownedLiquidity = dolaGauge.balanceOf(address(this));

        if (liquidityToWithdraw > ownedLiquidity) liquidityToWithdraw = ownedLiquidity;

        dolaGauge.withdraw(liquidityToWithdraw);

        LP_TOKEN.approve(address(router), liquidityToWithdraw);
        (uint amountDola, uint amountUSDC) = router.removeLiquidity(address(DOLA), address(USDC), true, liquidityToWithdraw, 0, 0, address(this), block.timestamp);

        (uint dolaReceivedAsUsdc,) = router.getAmountOut(amountUSDC, address(USDC), address(DOLA));
        uint totalDolaReceived = amountDola + dolaReceivedAsUsdc;

        if ((dolaAmount * (PRECISION - maxSlippageBpsLiquidity) / PRECISION) > totalDolaReceived) {
            revert LiquiditySlippageTooHigh();
        }

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

        USDC.approve(address(router), usdcAmount);
        router.swapExactTokensForTokensSimple(usdcAmount, minOut, address(USDC), address(DOLA), true, address(this), block.timestamp);
    }

    /**
    @notice Swap `dolaAmount` of DOLA to USDC through velodrome.
    @param dolaAmount Amount of DOLA to swap to USDC
    */
    function swapDOLAtoUSDC(uint dolaAmount) public onlyChair { 
        uint minOut = dolaAmount * (PRECISION - maxSlippageBpsDolaToUsdc) / PRECISION / DOLA_USDC_CONVERSION_MULTI;
        
        DOLA.approve(address(router), dolaAmount);
        router.swapExactTokensForTokensSimple(dolaAmount, minOut, address(DOLA), address(USDC), true, address(this), block.timestamp);
    }

    /**
    @notice Calculates approximate price of 1 Velodrome DOLA/USDC stable pool LP token
    */
    function getLpTokenPrice(bool withdraw_) internal view returns (uint) {
        (uint dolaAmountOneLP, uint usdcAmountOneLP) = router.quoteRemoveLiquidity(address(DOLA), address(USDC), true, 0.001 ether);
        (uint dolaForRemovedUsdc,) = router.getAmountOut(usdcAmountOneLP, address(USDC), address(DOLA));
        (uint usdcForRemovedDola,) = router.getAmountOut(dolaAmountOneLP, address(DOLA), address(USDC));
        usdcForRemovedDola *= DOLA_USDC_CONVERSION_MULTI;
        usdcAmountOneLP *= DOLA_USDC_CONVERSION_MULTI;

        if (dolaAmountOneLP + dolaForRemovedUsdc > usdcAmountOneLP + usdcForRemovedDola && withdraw_) {
            return (dolaAmountOneLP + dolaForRemovedUsdc) * 1000;
        } else {
            return (usdcAmountOneLP + usdcForRemovedDola) * 1000;
        }
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
    function setMaxSlippageDolaToUsdc(uint newMaxSlippageBps) onlyGovOrGuardian external {
        if (newMaxSlippageBps > 10000) revert MaxSlippageTooHigh();
        maxSlippageBpsDolaToUsdc = newMaxSlippageBps;
    }

    /**
    @notice Governance only function for setting acceptable slippage when swapping USDC -> DOLA
    @param newMaxSlippageBps The new maximum allowed loss for USDC -> DOLA swaps. 1 = 0.01%
    */
    function setMaxSlippageUsdcToDola(uint newMaxSlippageBps) onlyGovOrGuardian external {
        if (newMaxSlippageBps > 10000) revert MaxSlippageTooHigh();
        maxSlippageBpsUsdcToDola = newMaxSlippageBps;
    }

    /**
    @notice Governance only function for setting acceptable slippage when adding or removing liquidty from DOLA/USDC pool
    @param newMaxSlippageBps The new maximum allowed loss for adding/removing liquidity from DOLA/USDC pool. 1 = 0.01%
    */
    function setMaxSlippageLiquidity(uint newMaxSlippageBps) onlyGovOrGuardian external {
        if (newMaxSlippageBps > 10000) revert MaxSlippageTooHigh();
        maxSlippageBpsLiquidity = newMaxSlippageBps;
    }

    /**
    @notice Method for `gov` to change `pendingGov` address
    @dev `pendingGov` will have to call `claimGov` to complete `gov` transfer
    @dev `pendingGov` should be an L1 address
    @param newPendingGov_ L1 address to be set as `pendingGov`
    */
    function setPendingGov(address newPendingGov_) onlyGov external {
        pendingGov = newPendingGov_;
    }

    /**
    @notice Helper function for approximating the amount of token1 that needs to be traded for token2 when adding liquidity.
    @param pool1Balance The balance of token1 in the Velodrome pair
    @param pool2Balance The balance of token2 in the Velodrome pair
    @param balance1 The balance of token1 to add for liquidity
    @param balance2 The balance of token2 to add for liquidity
    */
    function optimizeLP(uint pool1Balance, uint pool2Balance, uint balance1, uint balance2) public pure returns(uint balance1ForBalance2, uint balance2ForBalance1){
        uint fee = 2 * 1e14; //0.02%
        uint k1;
        uint k2 = pool1Balance + pool2Balance;
        if(pool2Balance * balance1 > pool1Balance * balance2){
            k1 = pool2Balance * balance1 - pool1Balance * balance2;
            balance1ForBalance2 = k1 * (1e18 - fee) / 1e18 / k2;
            balance2ForBalance1 = 0;
        } else {
            k1 = pool1Balance * balance2 - pool2Balance * balance1;
            balance1ForBalance2 = 0;           
            balance2ForBalance1 = k1 * (1e18 - fee) / 1e18 / k2;
        }
    }

    /**
    @notice Method for `pendingGov` to claim `gov` role.
    */
    function claimGov() external onlyPendingGov {
        gov = pendingGov;
        pendingGov = address(0);
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
    @notice Method for gov to change the guardian
    @param guardian_ L1 address to be set as guardian
    */
    function changeGuardian(address guardian_) external onlyGov {
        guardian = guardian_;
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
