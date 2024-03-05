pragma solidity ^0.8.13;

import "src/interfaces/IERC20.sol";
import "src/interfaces/balancer/IVault.sol";
import "src/interfaces/stakedao/IBalancerVault.sol";
import "src/interfaces/stakedao/IGauge.sol";
import "src/interfaces/stakedao/IClaimRewards.sol";
import "src/stakedao-fed/BalancerAdapter.sol";

contract StakeDaoFed is BalancerComposableStablepoolAdapter{

    IBalancerVault public balancerVault;
    IGauge public sdbaousdGauge;
    IClaimRewards public rewards;
    IERC20 public bal;
    IERC20 public std;
    address public chair;
    address public guardian;
    address public gov;
    uint public dolaSupply;
    uint public constant pid = 132; //Gauge pid, should never change
    uint public maxLossExpansionBps;
    uint public maxLossWithdrawBps;
    uint public maxLossTakeProfitBps;
    uint public maxLossSetableByGuardian = 500;

    event Expansion(uint amount);
    event Contraction(uint amount);

    struct InitialAddresses {
        address dola;
        address bal;
        address std;
        address vault;
        address bpt;
        address balancerVault;
        address sdbaousdGauge;
        address rewards;
        address chair;
        address guardian;
        address gov;
    }

    constructor(
            InitialAddresses memory addresses_,
            uint maxLossExpansionBps_,
            uint maxLossWithdrawBps_,
            uint maxLossTakeProfitBps_,
            bytes32 poolId_) 
            BalancerComposableStablepoolAdapter(poolId_, addresses_.dola, addresses_.vault, addresses_.bpt)
    {
        require(maxLossExpansionBps_ < 10000, "Expansion max loss too high");
        require(maxLossWithdrawBps_ < 10000, "Withdraw max loss too high");
        require(maxLossTakeProfitBps_ < 10000, "TakeProfit max loss too high");
        balancerVault = IBalancerVault(addresses_.balancerVault);
        sdbaousdGauge = IGauge(addresses_.sdbaousdGauge);
        rewards = IClaimRewards(addresses_.rewards);
        std = IERC20(addresses_.std);
        bal = IERC20(addresses_.bal);
        (address bpt,) = IVault(addresses_.vault).getPool(poolId_);
        IERC20(bpt).approve(addresses_.balancerVault, type(uint256).max);
        maxLossExpansionBps = maxLossExpansionBps_;
        maxLossWithdrawBps = maxLossWithdrawBps_;
        maxLossTakeProfitBps = maxLossTakeProfitBps_;
        chair = addresses_.chair;
        gov = addresses_.gov;
        guardian = addresses_.guardian;
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
    @notice Method for current chair of the STAKEDAO FED to resign
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
        require(msg.sender == gov || msg.sender == guardian, "ONLY GOV OR GUARDIAN");
        if(msg.sender == guardian){
            //We limit the max loss a guardian, as we only want governance to be able to set a very high maxloss 
            require(newMaxLossWithdrawBps <= maxLossSetableByGuardian, "Above allowed maxloss for chair");
        }
        require(newMaxLossWithdrawBps <= 10000, "Can't have max loss above 100%");
        maxLossWithdrawBps = newMaxLossWithdrawBps;
    }

    function setMaxLossTakeProfitBps(uint newMaxLossTakeProfitBps) public {
        require(msg.sender == gov, "ONLY GOV");
        require(newMaxLossTakeProfitBps <= 10000, "Can't have max loss above 100%");
        maxLossTakeProfitBps = newMaxLossTakeProfitBps;   
    }

    function setMaxLossSetableByGuardian(uint newMaxLossSetableByGuardian) public {
        require(msg.sender == gov, "ONLY GOV");
        require(newMaxLossSetableByGuardian < 10000);
        maxLossSetableByGuardian = newMaxLossSetableByGuardian;
    }
    /**
    @notice Deposits amount of dola tokens into balancer, before locking with stakedao
    @param amount Amount of dola token to deposit
    */
    function expansion(uint amount) public {
        require(msg.sender == chair, "ONLY CHAIR");
        dolaSupply += amount;
        IERC20(dola).mint(address(this), amount);
        _deposit(amount, maxLossExpansionBps);
        balancerVault.deposit(address(this), bpt.balanceOf(address(this)), true);
        emit Expansion(amount);
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
    function contraction(uint amountDola) public {
        require(msg.sender == chair, "ONLY CHAIR");
        //Calculate how many lp tokens are needed to withdraw the dola
        uint bptNeeded = bptNeededForDola(amountDola);
        require(bptNeeded <= bptSupply(), "Not enough BPT tokens");

        //Withdraw BPT tokens from stakedao, but don't claim rewards
        balancerVault.withdraw(bptNeeded);

        //Withdraw DOLA from balancer pool
        uint dolaWithdrawn = _withdraw(amountDola, maxLossWithdrawBps);
        require(dolaWithdrawn > 0, "Must contract");
        _burnAndPay();
        emit Contraction(dolaWithdrawn);
    }

    /**
    @notice Withdraws every remaining balLP token. Can take up to maxLossWithdrawBps in loss, compared to dolaSupply.
    It will still be necessary to call takeProfit to withdraw any potential rewards.
    */
    function contractAll() public {
        require(msg.sender == chair, "ONLY CHAIR");
        balancerVault.withdraw(sdbaousdGauge.balanceOf(address(this)));
        uint dolaWithdrawn = _withdrawAll(maxLossWithdrawBps);
        require(dolaWithdrawn > 0, "Must contract");
        _burnAndPay();
        emit Contraction(dolaWithdrawn);
    }

    /**
    @notice Burns all dola tokens held by the fed up to the dolaSupply, taking any surplus as profit.
    */
    function _burnAndPay() internal {
        uint dolaBal = dola.balanceOf(address(this));
        if(dolaBal > dolaSupply){
            IERC20(dola).transfer(gov, dolaBal - dolaSupply);
            IERC20(dola).burn(dolaSupply);
            dolaSupply = 0;
        } else {
            IERC20(dola).burn(dolaBal);
            dolaSupply -= dolaBal;
        }
    }

    /**
    @notice Withdraws the profit generated by stakedao staking
    @dev See dev note on Contraction method
    */
    function takeProfit(bool harvestLP) public {
        //This takes balLP at face value, but doesn't take into account slippage or fees
        //Worth considering that the additional transaction fees incurred by withdrawing the small amount of profit generated by tx fees,
        //may not eclipse additional transaction costs. Set harvestLP = false to only withdraw bal and stakedao rewards.
        uint bptValue = bptSupply() * bpt.getRate() / 10**18;
        if(harvestLP && bptValue > dolaSupply) {
            require(msg.sender == chair, "ONLY CHAIR CAN TAKE BPT PROFIT");
            uint dolaSurplus = bptValue - dolaSupply;
            uint bptToWithdraw = bptNeededForDola(dolaSurplus);
            if(bptToWithdraw > sdbaousdGauge.balanceOf(address(this))){
                bptToWithdraw = sdbaousdGauge.balanceOf(address(this));
            }
            balancerVault.withdraw(bptToWithdraw);
            uint dolaProfit = _withdraw(dolaSurplus, maxLossTakeProfitBps);
            require(dolaProfit > 0, "NO PROFIT");
            dola.transfer(gov, dolaProfit);
        }

        address[] memory baoGaugeArray = new address[](1);
        baoGaugeArray[0] = address(sdbaousdGauge);
        rewards.claimRewards(baoGaugeArray);
        bal.transfer(gov, bal.balanceOf(address(this)));
        std.transfer(gov, std.balanceOf(address(this)));
    }

    /**
    @notice Burns the remaining dola supply in case the FED has been completely contracted, and still has a negative dola balance.
    */
    function burnRemainingDolaSupply() public {
        dola.transferFrom(msg.sender, address(this), dolaSupply);
        dola.burn(dolaSupply);
        dolaSupply = 0;
    }
    
    /**
    @notice View function for getting bpt tokens in the contract + stakedao baousdgauge 
    */
    function bptSupply() public view returns(uint){
        return IERC20(bpt).balanceOf(address(this)) + sdbaousdGauge.balanceOf(address(this));
    }

    function recoverERC20(address tokenAddress, uint256 amount) public {
        require(msg.sender == gov, "ONLY GOV CAN RESCUE TOKENS");
        IERC20 token = IERC20(tokenAddress);
        uint256 contractBalance = token.balanceOf(address(this));
        require(contractBalance >= amount, "Contract balance is insufficient");

        bool success = token.transfer(gov, amount);
        require(success, "Token transfer failed");
    }
}
