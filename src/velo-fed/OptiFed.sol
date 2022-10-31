pragma solidity ^0.8.13;

import "../interfaces/IERC20.sol";
import "../interfaces/velo/IDola.sol";
import "../interfaces/velo/IL1ERC20Bridge.sol";
import "../interfaces/velo/ICurvePool.sol";

contract OptiFed {
    address public chair;
    address public gov;
    uint public underlyingSupply;
    uint public maxSlippageBpsDolaToUsdc;
    uint public maxSlippageBpsUsdcToDola;
    uint public lastDeltaUpdate;
    uint public maxDailyDelta;
    uint private dailyDelta;

    uint constant PRECISION = 10_000;

    IDola public immutable DOLA = IDola(0x865377367054516e17014CcdED1e7d814EDC9ce4);
    IERC20 public immutable USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IL1ERC20Bridge public immutable optiBridge = IL1ERC20Bridge(0x99C9fc46f92E8a1c0deC1b1747d010903E884bE1);
    address public immutable DOLA_OPTI = 0x8aE125E8653821E851F12A49F7765db9a9ce7384;
    address public immutable USDC_OPTI = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
    ICurvePool public immutable curvePool = ICurvePool(0xAA5A67c256e27A5d80712c51971408db3370927D);
    address public veloFarmer;

    event Expansion(uint amount);
    event Contraction(uint amount);

    error OnlyGov();
    error OnlyChair();
    error CantBurnZeroDOLA();
    error MaxSlippageTooHigh();
    error DeltaAboveMax();

    constructor(
            address gov_,
            address veloFarmer_,
            uint maxDailyDelta_)
    {
        chair = msg.sender;
        gov = gov_;
        veloFarmer = veloFarmer_;
        maxDailyDelta = maxDailyDelta_; 
        lastDeltaUpdate = block.timestamp - 1 days;

        DOLA.approve(address(optiBridge), type(uint).max);
        USDC.approve(address(optiBridge), type(uint).max);
        DOLA.approve(address(curvePool), type(uint).max);
        USDC.approve(address(curvePool), type(uint).max);
    }

    /**
    @notice Mints `amountUnderlying` of `underlying` tokens, swaps half to USDC, then transfers all to `veloFarmer` through optimism bridge
    @param amountUnderlying Amount of underlying token to mint
    */
    function expansionAndSwap(uint amountUnderlying) external {
        if (msg.sender != chair) revert OnlyChair();
        
        _updateDailyDelta(amountUnderlying);
        underlyingSupply += amountUnderlying;
        DOLA.mint(address(this), amountUnderlying);

        curvePool.exchange_underlying(0, 2, amountUnderlying / 2, 0);

        optiBridge.depositERC20To(address(DOLA), DOLA_OPTI, veloFarmer, DOLA.balanceOf(address(this)), 200_000, "");
        optiBridge.depositERC20To(address(USDC), USDC_OPTI, veloFarmer, USDC.balanceOf(address(this)), 200_000, "");

        emit Expansion(amountUnderlying);
    }

    /**
    @notice Mints & deposits `amountUnderlying` of `underlying` tokens into Optimism bridge to the `veloFarmer` contract
    @param amountUnderlying Amount of underlying token to mint & deposit into Velodrome farmer on Optimism
    */
    function expansion(uint amountUnderlying) external {
        if (msg.sender != chair) revert OnlyChair();
        
        _updateDailyDelta(amountUnderlying);
        underlyingSupply += amountUnderlying;
        DOLA.mint(address(this), amountUnderlying);

        optiBridge.depositERC20To(address(DOLA), DOLA_OPTI, veloFarmer, DOLA.balanceOf(address(this)), 200_000, "");

        emit Expansion(amountUnderlying);
    }

    /**
    @notice Burns `amountUnderlying` of DOLA held in this contract
    */
    function contraction(uint amountUnderlying) public {
        if (msg.sender != chair) revert OnlyChair();

        _contraction(amountUnderlying);
    }

    /**
    @notice Attempts to contract (burn) all DOLA held by this contract
    */
    function contractAll() external {
        if (msg.sender != chair) revert OnlyChair();

        _contraction(DOLA.balanceOf(address(this)));
    }

    /**
    @notice Attempts to contract (burn) `amount` of DOLA. Sends remainder to `gov` if `amount` > DOLA minted by this fed.
    */
    function _contraction(uint amount) internal{
        if (amount == 0) revert CantBurnZeroDOLA();
        if(amount > underlyingSupply){
            DOLA.burn(underlyingSupply);
            _updateDailyDelta(underlyingSupply);
            DOLA.transfer(gov, amount - underlyingSupply);
            emit Contraction(underlyingSupply);
            underlyingSupply = 0;
        } else {
            DOLA.burn(amount);
            _updateDailyDelta(amount);
            underlyingSupply -= amount;
            emit Contraction(amount);
        }
    }

    /**
    @notice Swap `usdcAmount` of USDC for DOLA through curve. Will revert if actual slippage > `maxSlippageBpsUsdcToDola`
    */
    function swapUSDCtoDOLA(uint usdcAmount) external {
        if (msg.sender != chair) revert OnlyChair();
        
        curvePool.exchange_underlying(2, 0, usdcAmount, usdcAmount * (PRECISION - maxSlippageBpsUsdcToDola) / PRECISION);
    }

    /**
    @notice Swap `dolaAmount` of DOLA for USDC through curve. Will revert if actual slippage > `maxSlippageBpsDolaToUsdc`
    */
    function swapDOLAtoUSDC(uint dolaAmount) external {
        if (msg.sender != chair) revert OnlyChair();
        
        curvePool.exchange_underlying(0, 2, dolaAmount, dolaAmount * (PRECISION - maxSlippageBpsDolaToUsdc) / PRECISION);
    }

    /**
    @notice Method for current chair of the Opti FED to resign
    */
    function resign() external {
        if (msg.sender != chair) revert OnlyChair();
        chair = address(0);
    }
    
    /**
    @notice Updates dailyDelta and lastDeltaUpdate
    @dev This is the only way you should update dailyDelta or lastDeltaUpdate!
    @param delta The delta the dailyDelta is updated with
    */
    function _updateDailyDelta(uint delta) internal {
        //If statement isn't strictly necessary, but saves gas as long as function is called less than daily
        if(lastDeltaUpdate + 1 days <= block.timestamp){
            dailyDelta = delta;
        } else {
            uint freedDelta = maxDailyDelta * (block.timestamp - lastDeltaUpdate) / 1 days;
            dailyDelta = freedDelta >= dailyDelta ? delta : dailyDelta - freedDelta + delta;
        }
        if (dailyDelta > maxDailyDelta) revert DeltaAboveMax();
        lastDeltaUpdate = block.timestamp;
    }

    /**
    @notice Governance only function for setting maximum daily DOLA supply delta allowed for the fed
    @param newMaxDailyDelta The new maximum amount underlyingSupply can be expanded or contracted in a day
    */
    function setMaxDailyDelta(uint newMaxDailyDelta) external {
        if (msg.sender != gov) revert OnlyGov();
        maxDailyDelta = newMaxDailyDelta;
    }

    /**
    @notice Governance only function for setting acceptable slippage when swapping DOLA -> USDC
    @param newMaxSlippageBps The new maximum allowed loss for DOLA -> USDC swaps. 1 = 0.01%
    */
    function setMaxSlippageDolaToUsdc(uint newMaxSlippageBps) external {
        if (msg.sender != gov) revert OnlyGov();
        if (newMaxSlippageBps > 10000) revert MaxSlippageTooHigh();
        maxSlippageBpsDolaToUsdc = newMaxSlippageBps;
    }

    /**
    @notice Governance only function for setting acceptable slippage when swapping USDC -> DOLA
    @param newMaxSlippageBps The new maximum allowed loss for USDC -> DOLA swaps. 1 = 0.01%
    */
    function setMaxSlippageUsdcToDola(uint newMaxSlippageBps) external {
        if (msg.sender != gov) revert OnlyGov();
        if (newMaxSlippageBps > 10000) revert MaxSlippageTooHigh();
        maxSlippageBpsUsdcToDola = newMaxSlippageBps;
    }

    /**
    @notice View function for reading the available daily delta
    */
    function availableDailyDelta() public view returns(uint){
        uint freedDelta = maxDailyDelta * (block.timestamp - lastDeltaUpdate) / 1 days;
        return freedDelta >= dailyDelta ? maxDailyDelta : maxDailyDelta - dailyDelta + freedDelta;
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
    @notice Method for gov to change the L2 veloFarmer address
    */
     function changeVeloFarmer(address newVeloFarmer_) external {
        if (msg.sender != gov) revert OnlyGov();
        veloFarmer = newVeloFarmer_;
    }
}