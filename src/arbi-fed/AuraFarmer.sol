pragma solidity ^0.8.13;

import "src/interfaces/IERC20.sol";
import "src/interfaces/balancer/IVault.sol";
import "src/interfaces/aura/IAuraLocker.sol";
import "src/interfaces/aura/IAuraBalRewardPool.sol";
import "src/aura-fed/BalancerAdapter.sol";
import {IL2GatewayRouter} from "src/interfaces/arbitrum/IL2GatewayRouter.sol";

interface IAuraBooster {
    function depositAll(uint _pid, bool _stake) external;
    function withdraw(uint _pid, uint _amount) external;
}

library AddressAliasHelper {
    uint160 constant offset = uint160(0x1111000000000000000000000000000000001111);

    /// @notice Utility function that converts the address in the L1 that submitted a tx to
    /// the inbox to the msg.sender viewed in the L2
    /// @param l1Address the address in the L1 that triggered the tx to L2
    /// @return l2Address L2 address as viewed in msg.sender
    function applyL1ToL2Alias(address l1Address) internal pure returns (address l2Address) {
        l2Address = address(uint160(l1Address) + offset);
    }

    /// @notice Utility function that converts the msg.sender viewed in the L2 to the
    /// address in the L1 that submitted a tx to the inbox
    /// @param l2Address L2 address as viewed in msg.sender
    /// @return l1Address the address in the L1 that triggered the tx to L2
    function undoL1ToL2Alias(address l2Address) internal pure returns (address l1Address) {
        l1Address = address(uint160(l2Address) - offset);
    }
}

contract AuraFarmer is BalancerComposableStablepoolAdapter{

    IAuraBalRewardPool public dolaBptRewardPool;
    IAuraBooster public booster;
   
    address public chair; // Fed Chair
    address public l2chair;
    address public guardian;
    address public gov;
    uint public dolaDeposited; // TODO: use this to calculate the amount of DOLA to deposit and if we have profit
    uint public dolaProfit; // TODO: review this variable accounting
    uint public constant pid = 8; // TODO: use proper pid , Gauge pid, should never change 
    uint public maxLossExpansionBps;
    uint public maxLossWithdrawBps;
    uint public maxLossTakeProfitBps;
    uint public maxLossSetableByGuardian = 500;

    // Actual addresses
    IL2GatewayRouter public immutable l2Gateway = IL2GatewayRouter(0x5288c571Fd7aD117beA99bF60FE0846C4E84F933); 
    IERC20 public immutable DOLAL1 = IERC20(0x865377367054516e17014CcdED1e7d814EDC9ce4);
    IERC20 public immutable auraL1 = IERC20(0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF);
    IERC20 public immutable balL1 = IERC20(0xba100000625a3754423978a60c9317c58a424e3D);

    // TODO: update addresses
    IERC20 public bal = IERC20(0x99C9fc46f92E8a1c0deC1b1747d010903E884bE1);
    IERC20 public immutable aura = IERC20(0x99C9fc46f92E8a1c0deC1b1747d010903E884bE1);

    address public arbiFedL1;
    address public arbiMessengerL1;

    event Deposit(uint amount);
    event Withdraw(uint amount);

    error OnlyChair();
    error OnlyGov();
    error OnlyArbiMessengerL1();
    error MaxSlippageTooHigh();
    error NotEnoughTokens();

    // TODO: reformat constructor, add arbi fed and messenger
    constructor(
            address dola_,
            address vault_,
            address dolaBptRewardPool_, 
            address booster_,
            address chair_,
            address guardian_,
            address gov_, 
            uint maxLossExpansionBps_,
            uint maxLossWithdrawBps_,
            uint maxLossTakeProfitBps_,
            bytes32 poolId_
            ) 
            BalancerComposableStablepoolAdapter(poolId_, dola_, vault_)
    {
        require(maxLossExpansionBps_ < 10000, "Expansion max loss too high");
        require(maxLossWithdrawBps_ < 10000, "Withdraw max loss too high");
        require(maxLossTakeProfitBps_ < 10000, "TakeProfit max loss too high");
        dolaBptRewardPool = IAuraBalRewardPool(dolaBptRewardPool_);
        booster = IAuraBooster(booster_);
        bal = IERC20(dolaBptRewardPool.rewardToken());
        (address bpt,) = IVault(vault_).getPool(poolId_);
        IERC20(bpt).approve(booster_, type(uint256).max);
        maxLossExpansionBps = maxLossExpansionBps_;
        maxLossWithdrawBps = maxLossWithdrawBps_;
        maxLossTakeProfitBps = maxLossTakeProfitBps_;
        chair = chair_;
        gov = gov_;
        guardian = guardian_;
    }

    // TODO: update modifiers with proper gov chair and messenger 
    // TODO: review gov chair guardian roles
    modifier onlyGov() {
        if(AddressAliasHelper.undoL1ToL2Alias(msg.sender) != arbiMessengerL1) revert OnlyArbiMessengerL1();
        _;
    }

    modifier onlyChair() {
        if(AddressAliasHelper.undoL1ToL2Alias(msg.sender) != arbiMessengerL1) revert OnlyArbiMessengerL1();
        _;
    }

    /**
    @notice Method for gov to change gov address
    */
    function changeGov(address newGov_) onlyGov external {
        gov = newGov_;
    }

    /**
    @notice Method for gov to change the chair
    */
    function changeChair(address newChair_) onlyGov external {
        chair = newChair_;
    }

    function changeArbiFedL1(address newArbiFedL1_) onlyGov external {
        arbiFedL1 = newArbiFedL1_;
    }

    function changeArbiMessengerL1(address newArbiMessengerL1_) onlyGov external {
        arbiMessengerL1 = newArbiMessengerL1_;
    }

    /**
    @notice Method for current chair of the Aura FED to resign
    */
    function resign() onlyChair external {
        chair = address(0);
    }

    function setMaxLossExpansionBps(uint newMaxLossExpansionBps) onlyGov external {
        require(newMaxLossExpansionBps <= 10000, "Can't have max loss above 100%");
        maxLossExpansionBps = newMaxLossExpansionBps;
    }

    function setMaxLossWithdrawBps(uint newMaxLossWithdrawBps) external {
        require(AddressAliasHelper.undoL1ToL2Alias(msg.sender) == arbiMessengerL1 || msg.sender == guardian, "ONLY GOV OR CHAIR");
        if(msg.sender == guardian){
            //We limit the max loss a guardian, as we only want governance to be able to set a very high maxloss 
            require(newMaxLossWithdrawBps <= maxLossSetableByGuardian, "Above allowed maxloss for chair");
        }
        require(newMaxLossWithdrawBps <= 10000, "Can't have max loss above 100%");
        maxLossWithdrawBps = newMaxLossWithdrawBps;
    }

    function setMaxLossTakeProfitBps(uint newMaxLossTakeProfitBps) onlyGov external {
        require(newMaxLossTakeProfitBps <= 10000, "Can't have max loss above 100%");
        maxLossTakeProfitBps = newMaxLossTakeProfitBps;   
    }

    function setMaxLossSetableByGuardian(uint newMaxLossSetableByGuardian) external {
        require(msg.sender == guardian, "ONLY GOV OR CHAIR");
        require(newMaxLossSetableByGuardian < 10000);
        maxLossSetableByGuardian = newMaxLossSetableByGuardian;
    }
    /**
    @notice Deposits amount of dola tokens into balancer, before locking with aura
    @param amount Amount of dola token to deposit
    */
    function deposit(uint amount) onlyChair external {
        dolaDeposited += amount;
        _deposit(amount, maxLossExpansionBps);
        booster.depositAll(pid, true);
        emit Deposit(amount); // Amount of dola deposited into balancer
    }
    /**
    @notice Withdraws an amount of dola token to be burnt, contracting DOLA dolaSupply
    @dev Be careful when setting maxLoss parameter. There will almost always be some loss from
    slippage + trading fees that may be incurred when withdrawing from a Balancer pool.
    On the other hand, setting the maxLoss too high, may cause you to be front run by MEV
    sandwhich bots, making sure your entire maxLoss is incurred.
    Recommended to always broadcast withdrawl transactions(contraction & takeProfits)
    through a frontrun protected RPC like Flashbots RPC.
    @param amountDola The amount of dola tokens to withdraw. Note that more tokens may
    be withdrawn than requested, as price is calculated by debts to strategies, but strategies
    may have outperformed price of dola token.
    */
    function withdrawLiquidity(uint amountDola) onlyChair external {
        require(msg.sender == chair, "ONLY CHAIR");
        //Calculate how many lp tokens are needed to withdraw the dola
        uint bptNeeded = bptNeededForDola(amountDola);
        require(bptNeeded <= bptSupply(), "Not enough BPT tokens");

        //Withdraw BPT tokens from aura, but don't claim rewards
        require(dolaBptRewardPool.withdrawAndUnwrap(bptNeeded, false), "AURA WITHDRAW FAILED");


        //Withdraw DOLA from balancer pool
        uint dolaWithdrawn = _withdraw(amountDola, maxLossWithdrawBps);
        require(dolaWithdrawn > 0, "Nothing withdrawn");

        if(dolaWithdrawn >= dolaDeposited) {
            dolaDeposited = 0;
            dolaProfit += dolaWithdrawn - dolaDeposited;
        } else {
            dolaDeposited -= dolaWithdrawn;
        }

        emit Withdraw(dolaWithdrawn);
    }

    /**
    @notice Withdraws every remaining balLP token. Can take up to maxLossWithdrawBps in loss, compared to dolaSupply.
    It will still be necessary to call takeProfit to withdraw any potential rewards.
    */
    function withdrawAllLiquidity() onlyChair external {
  
        require(dolaBptRewardPool.withdrawAndUnwrap(dolaBptRewardPool.balanceOf(address(this)), false), "AURA WITHDRAW FAILED");
        uint dolaWithdrawn = _withdrawAll(maxLossWithdrawBps);
        require(dolaWithdrawn > 0, "Nothing withdrawn");

        if(dolaWithdrawn >= dolaDeposited) {
            dolaDeposited = 0;
            dolaProfit += dolaWithdrawn - dolaDeposited;
        } else {
            dolaDeposited -= dolaWithdrawn;
        }

        emit Withdraw(dolaWithdrawn);
    }

    /**
    @notice Withdraws the profit generated by aura staking
    @dev See dev note on Contraction method
    */
    // TODO: review this function and adjust for L2 (review dolaDeposited and dolaProfit logic and edge cases)
    function takeProfit(bool harvestLP) public {
        //This takes balLP at face value, but doesn't take into account slippage or fees
        //Worth considering that the additional transaction fees incurred by withdrawing the small amount of profit generated by tx fees,
        //may not eclipse additional transaction costs. Set harvestLP = false to only withdraw bal and aura rewards.

        uint bptValue = bptSupply() * bpt.getRate() / 10**18;
        if(harvestLP && bptValue > dolaDeposited) {
            require(msg.sender == chair, "ONLY CHAIR CAN TAKE BPT PROFIT");
            uint dolaSurplus = bptValue - dolaDeposited;
            uint bptToWithdraw = bptNeededForDola(dolaSurplus);
            if(bptToWithdraw > dolaBptRewardPool.balanceOf(address(this))){
                bptToWithdraw = dolaBptRewardPool.balanceOf(address(this));
            }
            require(dolaBptRewardPool.withdrawAndUnwrap(bptToWithdraw, false), "AURA WITHDRAW FAILED");
            uint dolaProfit_ = _withdraw(dolaSurplus, maxLossTakeProfitBps);
            require(dolaProfit_ > 0, "NO PROFIT");
            dolaProfit += dolaProfit_;
        }

        require(dolaBptRewardPool.getReward(address(this), true), "Getting reward failed");
    }
    
    // Bridiging back to L1 TODO: review this bridging code
    /**
    @notice Withdraws `dolaAmount` of DOLA to arbiFed on L1. Will take 7 days before withdraw is claimable on L1.
    */
    function withdrawToL1ArbiFed(uint dolaAmount) external onlyChair {
        if (dolaAmount > dola.balanceOf(address(this))) revert NotEnoughTokens();

        l2Gateway.outboundTransfer(address(DOLAL1), arbiFedL1, dolaAmount,"");
    }

        /**
    @notice Withdraws `amount` of `l2Token` to address `to` on L1. Will take 7 days before withdraw is claimable.
    */
    function withdrawTokensToL1(address l1Token,address l2Token, address to, uint amount) external onlyChair {
        if (amount > IERC20(l2Token).balanceOf(address(this))) revert NotEnoughTokens();

        l2Gateway.outboundTransfer(address(l1Token), to, amount, "");
    }

    /**
    @notice View function for getting bpt tokens in the contract + aura dolaBptRewardPool
    */
    function bptSupply() public view returns(uint){
        return IERC20(bpt).balanceOf(address(this)) + dolaBptRewardPool.balanceOf(address(this));
    }
}
