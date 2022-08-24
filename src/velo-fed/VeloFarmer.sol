pragma solidity ^0.8.13;

import "../interfaces/IERC20.sol";
import {IRouter} from "../interfaces/IRouter.sol";
import {IGauge} from "../interfaces/IGauge.sol";
import {IRewardsDistributor} from "../interfaces/IRewards.sol";
import {IL2ERC20Bridge} from "../interfaces/IL2ERC20Bridge.sol";

contract VeloFarmer {
    address public chair;
    address public gov;
    uint public maxSlippageBps;

    uint public constant DOLA_USDC_CONVERSION_MULTI= 1e12;
    uint public constant PRECISION = 10_000;

    IRouter public immutable router;
    IRewardsDistributor public immutable rewards;
    IGauge public immutable dolaGauge = IGauge(0xAFD2c84b9d1cd50E7E18a55e419749A6c9055E1F);
    IERC20 public immutable DOLA;
    IERC20 public immutable USDC;
    IERC20 public immutable LP_TOKEN = IERC20(0x6C5019D345Ec05004A7E7B0623A91a0D9B8D590d);
    address public immutable veloTokenAddr = 0x3c8B650257cFb5f272f799F5e2b4e65093a11a05;
    IL2ERC20Bridge public immutable bridge;
    address public optiFed;

    error OnlyChair();
    error OnlyGov();
    error MaxSlippageTooHigh();
    error NotEnoughTokens();
    
    constructor(
            address payable routerAddr_, 
            address rewardsAddr_, 
            address dolaAddr_, 
            address usdcAddr_,
            address gov_,
            address bridge_,
            address optiFed_
        )
    {
        router = IRouter(routerAddr_);
        rewards = IRewardsDistributor(rewardsAddr_);
        DOLA = IERC20(dolaAddr_);
        USDC = IERC20(usdcAddr_);
        chair = msg.sender;
        gov = gov_;
        bridge = IL2ERC20Bridge(bridge_);
        optiFed = optiFed_;
        
        DOLA.approve(routerAddr_, type(uint256).max);
        USDC.approve(routerAddr_, type(uint256).max);
        LP_TOKEN.approve(address(dolaGauge), type(uint).max);
        LP_TOKEN.approve(address(router), type(uint).max);
    }

    /**
    @notice Claims all Velodrome VELO token rewards accrued by this contract
    */
    function claimVeloRewards() external {
        address[] memory addr = new address[](1);
        addr[0] = veloTokenAddr;
        dolaGauge.getReward(address(this), addr);
    }

    /**
    @notice Attempts to claim Velodrome token rewards.
    @param addrs Array of token addresses to claim rewards of.
    */
    function claimRewards(address[] calldata addrs) external {
        dolaGauge.getReward(address(this), addrs);
    }

    /**
    @notice Swaps half of `dolaAmount` into USDC through Velodrome. Adds liquidity to DOLA/USDC pool, then deposits LP tokens into DOLA gauge.
    */
    function swapAndDeposit(uint dolaAmount) external {
        if (msg.sender != chair) revert OnlyChair();

        uint halfDolaAmount = dolaAmount / 2;
        uint minOut = halfDolaAmount * maxSlippageBps / PRECISION / DOLA_USDC_CONVERSION_MULTI;
        uint[] memory amounts = router.swapExactTokensForTokensSimple(halfDolaAmount, minOut, address(DOLA), address(USDC), true, address(this), block.timestamp);
        router.addLiquidity(address(DOLA), address(USDC), true, halfDolaAmount, amounts[amounts.length - 1], 0, 0, address(this), block.timestamp);
        dolaGauge.deposit(LP_TOKEN.balanceOf(address(this)), 0);
    }

    /**
    @notice Attempts to deposit `dolaAmount` of DOLA & `usdcAmount` of USDC into Velodrome DOLA/USDC stable pool. Then, deposits LP tokens into gauge.
    */
    function deposit(uint dolaAmount, uint usdcAmount) public {
        if (msg.sender != chair) revert OnlyChair();

        router.addLiquidity(address(DOLA), address(USDC), true, dolaAmount, usdcAmount, 0, 0, address(this), block.timestamp);
        dolaGauge.deposit(LP_TOKEN.balanceOf(address(this)), 0);
    }

    /**
    @notice Calls `deposit()` with entire DOLA & USDC token balance of this contract.
    */
    function depositAll() external {
        deposit(DOLA.balanceOf(address(this)), USDC.balanceOf(address(this)));
    }

    /**
    @notice Withdraws `percent`% of LP tokens from gauge. Then, redeems LP tokens for DOLA/USDC and swaps redeemed USDC to DOLA.
    */
    function withdrawLiquidityAndSwapToDOLA(uint percent) external {
        uint usdcAmount = withdrawLiquidity(percent);

        swapUSDCtoDOLA(usdcAmount);
    }

    /**
    @notice Withdraws `dolaAmount` of DOLA to optiFed on L1. Will take 7 days before withdraw is claimable on L1.
    */
    function withdrawToL1OptiFed(uint dolaAmount) external {
        if (msg.sender != chair) revert OnlyChair();
        if (dolaAmount < DOLA.balanceOf(address(this))) revert NotEnoughTokens();

        bridge.withdrawTo(address(DOLA), optiFed, dolaAmount, 0, "");
    }

    /**
    @notice Withdraws `dolaAmount` of DOLA & `usdcAmount` of USDC to optiFed on L1. Will take 7 days before withdraw is claimable on L1.
    */
    function withdrawToL1OptiFed(uint dolaAmount, uint usdcAmount) external {
        if (msg.sender != chair) revert OnlyChair();
        if (dolaAmount < DOLA.balanceOf(address(this))) revert NotEnoughTokens();
        if (usdcAmount < USDC.balanceOf(address(this))) revert NotEnoughTokens();

        bridge.withdrawTo(address(DOLA), optiFed, dolaAmount, 0, "");
        bridge.withdrawTo(address(USDC), optiFed, usdcAmount, 0, "");
    }

    /**
    @notice Withdraws `amount` of `l2Token` to address `to` on L1. Will take 7 days before withdraw is claimable.
    */
    function withdrawTokensToL1(address l2Token, address to, uint amount) external {
        if (msg.sender != chair) revert OnlyChair();
        if (amount < IERC20(l2Token).balanceOf(address(this))) revert NotEnoughTokens();

        IERC20(l2Token).approve(address(bridge), amount);
        bridge.withdrawTo(address(l2Token), to, amount, 0, "");
    }

    /**
    @notice Allows `gov` to transfer tokens on this contract's behalf.
    */
    function transferTokens(address token, address to, uint amount) external {
        if (msg.sender != gov) revert OnlyGov();
        if (amount < IERC20(token).balanceOf(address(this))) revert NotEnoughTokens();

        require(IERC20(token).transfer(to, amount), "Token transfer failed");
    }

    /**
    @notice Withdraws `percent`% of LP tokens from gauge. Then, redeems LP tokens for DOLA/USDC.
    */
    function withdrawLiquidity(uint percent) public returns (uint) {
        if (msg.sender != chair) revert OnlyChair();

        uint withdrawAmount = IERC20(address(dolaGauge)).balanceOf(address(this)) * percent / 100;
        dolaGauge.withdraw(withdrawAmount);
        (, uint amountUSDC) = router.removeLiquidity(address(DOLA), address(USDC), true, withdrawAmount, 0, 0, address(this), block.timestamp);
        return amountUSDC;
    }

    /**
    @notice Swap `usdcAmount` of USDC to DOLA through velodrome.
    */
    function swapUSDCtoDOLA(uint usdcAmount) public {
        if (msg.sender != chair) revert OnlyChair();

        uint minOut = usdcAmount * maxSlippageBps / PRECISION * DOLA_USDC_CONVERSION_MULTI;
        router.swapExactTokensForTokensSimple(usdcAmount, minOut, address(USDC), address(DOLA), true, address(this), block.timestamp);
    }

    /**
    @notice Swap `dolaAmount` of DOLA to USDC through velodrome.
    */
    function swapDOLAtoUSDC(uint dolaAmount) public {
        if (msg.sender != chair) revert OnlyChair();
        
        uint minOut = dolaAmount * maxSlippageBps / PRECISION / DOLA_USDC_CONVERSION_MULTI;
        router.swapExactTokensForTokensSimple(dolaAmount, minOut, address(DOLA), address(USDC), true, address(this), block.timestamp);
    }

    /**
    @notice Method for current chair of the fed to resign
    */
    function resign() external {
        if (msg.sender != chair) revert OnlyChair();
        chair = address(0);
    }

    /**
    @notice Governance only function for setting acceptable slippage when swapping tokens
    @param newMaxSlippageBps The new maximum allowed loss for swaps. 1 = 0.01%
    */
    function setMaxSlippage(uint newMaxSlippageBps) external {
        if (msg.sender != gov) revert OnlyGov();
        if (newMaxSlippageBps > 10000) revert MaxSlippageTooHigh();
        maxSlippageBps = newMaxSlippageBps;
    }

    /**
    @notice Method for gov to change gov address
    */
    function changeGov(address newGov_) external {
        if (msg.sender != gov) revert OnlyGov();
        gov = newGov_;
    }

    /**
    @notice Method for gov to change the chair
    */
    function changeChair(address newChair_) external {
        if (msg.sender != gov) revert OnlyGov();
        chair = newChair_;
    }

    /**
    @notice Method for gov to change the L1 optiFed address
    */
    function changeOptiFed(address newOptiFed_) external {
        if (msg.sender != gov) revert OnlyGov();
        optiFed = newOptiFed_;
    }
}