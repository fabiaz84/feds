pragma solidity ^0.8.13;

import "src/interfaces/IERC20.sol";
import "src/interfaces/balancer/IVault.sol";
import "src/interfaces/aura/IAuraLocker.sol";
import "src/interfaces/aura/IAuraBalRewardPool.sol";
import "src/aura-fed/BalancerAdapter.sol";

contract AuraFed is BalancerMetapoolAdapter{

    IAuraBalRewardPool public baseRewardPool;
    IAuraLocker public locker;
    IERC20 public bal;
    IERC20 public auraBal;
    IERC20 public aura;
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
            address auraBal_,
            address aura_,
            address vault_,
            address baseRewardPool_, 
            address chair_,
            address gov_, 
            uint maxLossExpansionBps_,
            uint maxLossWithdrawBps_,
            uint maxLossTakeProfitBps_,
            bytes32 poolId_) 
            BalancerMetapoolAdapter(poolId_, dola_, vault_)
    {
        baseRewardPool = IAuraBalRewardPool(baseRewardPool_);
        locker = baseRewardPool.auraLocker();
        aura = IERC20(aura_);
        auraBal = IERC20(auraBal_);
        bal = IERC20(baseRewardPool.rewardToken());
        (address bpt,) = IVault(vault_).getPool(poolId_);
        //IERC20(bpt).approve(booster_, type(uint256).max);
        IERC20(bpt).approve(baseRewardPool_, type(uint256).max);
        maxLossExpansionBps = maxLossExpansionBps_;
        maxLossWithdrawBps = maxLossWithdrawBps_;
        maxLossTakeProfitBps = maxLossTakeProfitBps_;
        chair = chair_;
        gov = gov_;
        locker.delegate(chair);
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
        locker.delegate(newChair_);
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
    @notice Deposits amount of dola tokens into balancer, before locking with aura
    @param amount Amount of dola token to deposit
    */
    function expansion(uint amount) public {
        require(msg.sender == chair, "ONLY CHAIR");
        dolaSupply += amount;
        IERC20(dola).mint(address(this), amount);
        _deposit(amount, maxLossExpansionBps);
        require(baseRewardPool.stakeAll(), 'Failed Deposit');
        emit Expansion(amount);
    }

    /**
    @notice Withdraws an amount of dola token to be burnt, contracting DOLA dolaSupply
    @dev Be careful when setting maxLoss parameter. There will almost always be some loss,
    if the yEarn vault is forced to withdraw from dola strategies. 
    For example, slippage + trading fees may be incurred when withdrawing from a Balancer pool.
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
        uint bptNeeded = bptForDola(amountDola);
        require(bptNeeded <= bptSupply(), "Not enough BPT tokens");

        //Withdraw BPT tokens from aura, but don't claim rewards
        require(baseRewardPool.withdraw(bptNeeded, false, false), "AURA WITHDRAW FAILED");

        //Withdraw DOLA from curve pool
        uint dolaWithdrawn = _withdraw(amountDola, maxLossWithdrawBps);
        require(dolaWithdrawn > 0, "Must contract");
        if(dolaWithdrawn > dolaSupply){
            IERC20(dola).transfer(gov, dolaWithdrawn - dolaSupply);
            IERC20(dola).burn(dolaSupply);
            dolaSupply = 0;
        } else {
            IERC20(dola).burn(dolaWithdrawn);
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
        baseRewardPool.withdraw(baseRewardPool.balanceOf(address(this)), false, false);
        uint dolaMinOut = dolaSupply * (10_000 - maxLossWithdrawBps) / 10_000;
        //TODO: Set dolaOut properly
        uint dolaOut = 0;//zapDepositor.remove_liquidity_one_coin(crvMetapool, crvLpSupply(), 0, dolaMinOut);
        if(dolaOut > dolaSupply){
            IERC20(dola).transfer(gov, dolaOut - dolaSupply);
            IERC20(dola).burn(dolaSupply);
            dolaSupply = 0;
        } else {
            IERC20(dola).burn(dolaOut);
            dolaSupply -= dolaOut;
        }
        emit Contraction(dolaOut);
    }


    /**
    @notice Withdraws the profit generated by convex staking
    @dev See dev note on Contraction method
    */
    function takeProfit(bool harvestLP, bool lockClaims) public {
        //This takes crvLP at face value, but doesn't take into account slippage or fees
        //Worth considering that the additional transaction fees incurred by withdrawing the small amount of profit generated by tx fees,
        //may not eclipse additional transaction costs. Set harvestLP = false to only withdraw crv and cvx rewards.
        //TODO: Find way to calculate BPT value
        uint bptValue = 0;
        if(harvestLP && bptValue > dolaSupply) {
            require(msg.sender == chair, "ONLY CHAIR CAN TAKE BPT PROFIT");
            uint dolaSurplus = bptValue - dolaSupply;
            uint bptToWithdraw = bptForDola(dolaSurplus);
            require(baseRewardPool.withdraw(bptToWithdraw, false, false), "AURA WITHDRAW FAILED");
            uint dolaProfit = _withdraw(dolaSurplus, maxLossTakeProfitBps);
            require(dolaProfit > 0, "NO PROFIT");
            dola.transfer(gov, dolaProfit);
        }
        require(baseRewardPool.getReward(lockClaims));
        if(locker.balanceOf(address(this)) > 0){
            locker.getReward(address(this));
            address[] memory rewardTokens = locker.rewardTokens();
            for(uint i; i < rewardTokens.length; i++){
                //TODO: Can this be poisoned by bad tokens?
                IERC20(rewardTokens[i]).transfer(gov, IERC20(rewardTokens[i]).balanceOf(address(this)));
            }
        }
        bal.transfer(gov, bal.balanceOf(address(this)));
        if(!lockClaims){
            aura.transfer(gov, aura.balanceOf(address(this)));
        }
    }
    
    /**
    @notice View function for getting crvLP tokens in the contract + convex baseRewardPool
    */
    function bptSupply() public view returns(uint){
        return IERC20(bpt).balanceOf(address(this)) + baseRewardPool.balanceOf(address(this));
    }
}
