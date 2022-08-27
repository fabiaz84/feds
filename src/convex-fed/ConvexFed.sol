pragma solidity ^0.8.13;

import "src/interfaces/IERC20.sol";
import "src/interfaces/curve/IMetaPool.sol";
import "src/interfaces/convex/IConvexBooster.sol";
import "src/interfaces/convex/IConvexBaseRewardPool.sol";
import "src/convex-fed/CurvePoolAdapter.sol";

contract ConvexFed is CurvePoolAdapter{

    uint public immutable poolId;
    IConvexBooster public booster;
    IConvexBaseRewardPool public baseRewardPool;
    IERC20 public crv;
    IERC20 public CVX;
    address public chair; // Fed Chair
    address public gov;
    uint public dolaSupply;
    uint public maxLossExpansionBps;
    uint public maxLossWithdrawBps;
    uint public maxLossTakeProfitBps;

    event Expansion(uint amount);
    event Contraction(uint amount);

    constructor(
            address dola_, 
            address crv_,
            address CVX_,
            address crvPoolAddr,
            address zapDepositor,
            address booster_, 
            address baseRewardPool_, 
            address gov_, 
            uint maxLossExpansionBps_,
            uint maxLossWithdrawBps_,
            uint maxLossTakeProfitBps_,
            uint poolId_) 
            CurvePoolAdapter(dola_, crvPoolAddr, zapDepositor, 10**18)
    {
        booster = IConvexBooster(booster_);
        baseRewardPool = IConvexBaseRewardPool(baseRewardPool_);
        crv = IERC20(crv_);
        CVX = IERC20(CVX_);
        poolId = poolId_;
        IERC20(crvPoolAddr).approve(booster_, type(uint256).max);
        IERC20(crvPoolAddr).approve(baseRewardPool_, type(uint256).max);
        chair = msg.sender;
        maxLossExpansionBps = maxLossExpansionBps_;
        maxLossWithdrawBps = maxLossWithdrawBps_;
        maxLossTakeProfitBps = maxLossTakeProfitBps_;
        gov = gov_;
    }

    /**
    @notice Method for gov to change gov address
    */
    function changeGov(address newGov_) public {
        require(msg.sender == gov, "ONLY GOV");
        gov = newGov_;
    }

    /**
    @notice Method for gov to change the chair
    */
    function changeChair(address newChair_) public {
        require(msg.sender == gov, "ONLY GOV");
        chair = newChair_;
    }

    /**
    @notice Method for current chair of the Yearn FED to resign
    */
    function resign() public {
        require(msg.sender == chair, "ONLY CHAIR");
        chair = address(0);
    }

    function setMaxLossExpansionBps(uint newMaxLossExpansionBps) public {
        require(msg.sender == gov, "ONLY GOV");
        require(newMaxLossExpansionBps <= 10000, "Can't have max loss above 100%");
        maxLossExpansionBps = newMaxLossExpansionBps;
    }

    function setMaxLossWithdrawBps(uint newMaxLossWithdrawBps) public {
        require(msg.sender == gov, "ONLY GOV");
        require(newMaxLossWithdrawBps <= 10000, "Can't have max loss above 100%");
        maxLossWithdrawBps = newMaxLossWithdrawBps;
    }

    function setMaxLossTakeProfitBps(uint newMaxLossTakeProfitBps) public {
        require(msg.sender == gov, "ONLY GOV");
        require(newMaxLossTakeProfitBps <= 10000, "Can't have max loss above 100%");
        maxLossTakeProfitBps = newMaxLossTakeProfitBps;   
    }
    /**
    @notice Deposits amount of dola tokens into yEarn vault

    @param amount Amount of dola token to deposit into yEarn vault
    */
    function expansion(uint amount) public {
        require(msg.sender == chair, "ONLY CHAIR");
        dolaSupply += amount;
        dola.mint(address(this), amount);
        metapoolDeposit(amount, maxLossExpansionBps);
        require(booster.depositAll(poolId, true), 'Failed Deposit');
        emit Expansion(amount);
    }

    /**
    @notice Withdraws an amount of dola token to be burnt, contracting DOLA dolaSupply
    @dev Be careful when setting maxLoss parameter. There will almost always be some loss,
    if the yEarn vault is forced to withdraw from dola strategies. 
    For example, slippage + trading fees may be incurred when withdrawing from a Curve pool.
    On the other hand, setting the maxLoss too high, may cause you to be front run by MEV
    sandwhich bots, making sure your entire maxLoss is incurred.
    Recommended to always broadcast withdrawl transactions(contraction & takeProfits)
    through a frontrun protected RPC like Flashbots RPC.
    @param amountDola The amount of dola tokens to withdraw. Note that more tokens may
    be withdrawn than requested, as price is calculated by debts to strategies, but strategies
    may have outperformed price of dola token.
    */
    function contraction(uint amountDola) public {
        require(msg.sender == chair, "ONLY CHAIR");
        //Calculate how many lp tokens are needed to withdraw the dola
        uint crvLpNeeded = lpForDola(amountDola);
        require(crvLpNeeded <= crvLpSupply(), "Not enough crvLP tokens");

        //Withdraw and unwrap curveLP tokens from convex, but don't claim rewards
        require(baseRewardPool.withdrawAndUnwrap(crvLpNeeded, false), "CONVEX WITHDRAW FAILED");

        //Withdraw DOLA from curve pool
        uint dolaWithdrawn = metapoolWithdraw(amountDola, maxLossWithdrawBps);
        require(dolaWithdrawn > 0, "Must contract");
        if(dolaWithdrawn > dolaSupply){
            dola.transfer(gov, dolaWithdrawn - dolaSupply);
            dola.burn(dolaSupply);
            dolaSupply = 0;
        } else {
            dola.burn(dolaWithdrawn);
            dolaSupply = dolaSupply - dolaWithdrawn;
        }
        emit Contraction(dolaWithdrawn);
    }

    /**
    @notice Withdraws every remaining crvLP token. Can take up to maxLossWithdrawBps in loss, compared to dolaSupply.
    It will still be necessary to call takeProfit to withdraw any potential rewards.
    */
    function contractAll() public {
        require(msg.sender == chair, "ONLY CHAIR");
        baseRewardPool.withdrawAllAndUnwrap(false);
        uint dolaMinOut = dolaSupply * (10_000 - maxLossWithdrawBps) / 10_000;
        uint dolaOut = zapDepositor.remove_liquidity_one_coin(crvMetapool, crvLpSupply(), 0, dolaMinOut);
        if(dolaOut > dolaSupply){
            dola.transfer(gov, dolaOut - dolaSupply);
            dola.burn(dolaSupply);
            dolaSupply = 0;
        } else {
            dola.burn(dolaOut);
            dolaSupply -= dolaOut;
        }
        emit Contraction(dolaOut);
    }


    /**
    @notice Withdraws the profit generated by convex staking
    @dev See dev note on Contraction method
    */
    function takeProfit(bool harvestLP) public {
        //This takes crvLP at face value, but doesn't take into account slippage or fees
        //Worth considering that the additional transaction fees incurred by withdrawing the small amount of profit generated by tx fees,
        //may not eclipse additional transaction costs. Set harvestLP = false to only withdraw crv and cvx rewards.
        uint crvLpValue = IMetaPool(crvMetapool).get_virtual_price()*crvLpSupply() / 10**18;
        if(harvestLP && crvLpValue > dolaSupply) {
            require(msg.sender == chair, "ONLY CHAIR CAN TAKE CRV LP PROFIT");
            uint dolaSurplus = crvLpValue - dolaSupply;
            uint crvLpToWithdraw = lpForDola(dolaSurplus);
            require(baseRewardPool.withdrawAndUnwrap(crvLpToWithdraw, false), "CONVEX WITHDRAW FAILED");
            uint dolaProfit = metapoolWithdraw(dolaSurplus, maxLossTakeProfitBps);
            require(dolaProfit > 0, "NO PROFIT");
            dola.transfer(gov, dolaProfit);
        }
        //TODO: Withdraw directly to treasury?
        require(baseRewardPool.getReward());
        crv.transfer(gov, crv.balanceOf(address(this)));
        CVX.transfer(gov, CVX.balanceOf(address(this)));
    }
    
    /**
    @notice View function for getting crvLP tokens in the contract + convex baseRewardPool
    */
    function crvLpSupply() public view returns(uint){
        return IERC20(crvMetapool).balanceOf(address(this)) + baseRewardPool.balanceOf(address(this));
    }
}
