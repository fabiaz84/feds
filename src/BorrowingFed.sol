pragma solidity ^0.8.13;
import "src/interfaces/IERC20.sol";
import "src/BaseFed.sol";

abstract contract BorrowingFed is BaseFed{
    //Lender of DOLA who is in charge of burning and minting. Should be a dedicated smart contract
    address public lender;

    constructor(address _DOLA, address _gov, address _chair, address _lender) BaseFed(_DOLA, _gov, _chair){
        lender = _lender;
    }

    // ******************
    // * Access Control *
    // ******************

    modifier onlyLender(){
        require(msg.sender == lender || msg.sender == gov, "NOT LENDER OR GOV");
        _;
    }

    /**
     * @notice Sets the lender of the BorrowingFed. Only callable by gov
     * @param newLender The new address in charge of minting and burning
     */
    function setLender(address newLender) onlyGov external{
        lender = newLender;
        emit NewLender(newLender);
    }

    // **********************
    // * Abstract Functions *
    // **********************

    /**
     * @notice Internal function for depositing into the underlying market
     * @dev Must check against a max loss parameter when depositing into lossy markets
     * @param dolaAmount Amount of dola to deposit
     * @return claimsReceived Claims on the underlying market. Should be amount of receipt tokens or LP tokens. In case of no receipt tokens, return dolaAmount;
     */
    function _deposit(uint dolaAmount) internal virtual returns(uint claimsReceived);

    /**
     * @notice Internal function for withdrawing from the underlying market
     * @dev Must check against a max loss parameter when withdrawing from lossy markets
     * @param dolaAmount Amount of dola to attempt to withdraw
     * @return claimsUsed Amount of claims spent to withdraw from the underlying market
     * @return dolaReceived Amount of dola received. This number may be greater or less than the dolaAmount specified
     */
    function _withdraw(uint dolaAmount) internal virtual returns(uint claimsUsed, uint dolaReceived);

     /**
     * @notice Internal function for withdrawing all claims from the underlying market
     * @dev Must check against a max loss parameter when withdrawing from lossy markets
     * @return claimsUsed Amount of claims spent to withdraw from the underlying market. Shoud always be equal to claims.
     * @return dolaReceived Amount of dola received. This number may be greater or less than the debt of the contract.
     */   
    function _withdrawAll() internal virtual returns(uint claimsUsed, uint dolaReceived);

    /**
     * @notice Funtion for taking profit from profit generating feds.
     * @dev Must attempt to not take excessive profit
     * @dev Must NOT reduce debt
     * @dev Profits must be sent to governance
     * @param flag Flag for signalling certain profit taking behaviour.
       Some profit taking may be unsafe and should be permissioned to only chair,
       while other profit taking may be safe for all to call.
     */
    function takeProfit(uint flag) override external virtual;

    /**
     * @notice Function for withdrawing underlying of Fed in emergency.
       Can be useful in case of Fed accounting errors, hacks of underlying market or accidents.
     * @dev Will likely destroy all contract accounting. Use carefully. Should send withdrawn tokens to gov.
     */
    function emergencyWithdraw() onlyGov override external virtual{
        revert("NOT IMPLEMENTED");
    }

    // **********************
    // * Standard Functions *
    // **********************

    /**
     * @notice Internal function for paying down debt. Should be used in all functions that pay down DOLA debt,
     like contraction, contractAll and repayDebt.
     * @dev Will send any surplus DOLA to gov.
     * @dev Used by repayDebt, contraction and contractAll functions
     * @param amount Amount of debt to repay.
     */
    function _repayDebt(uint amount) override internal {
        if(amount > debt){
            uint sendAmount = amount - debt;
            uint burnAmount = debt;
            debt = 0;
            DOLA.transfer(gov, sendAmount);
            emit Profit(address(DOLA), sendAmount);
            emit Contraction(burnAmount);
        } else {
            debt -= amount;
            emit Contraction(amount);
        }
    }

    /**
     * @notice Function for expanding DOLA into a given fed market.
     * @param amount Amount of DOLA to mint and expand into the fed.
     * @dev May fail due to exceeding max loss parameters when depositing to lossy markets
     */
    function expansion(uint amount) onlyChair override external {
        debt += amount;
        claims += _deposit(amount);
        emit Expansion(amount);
    }

    /**
     * @notice Function for contracting DOLA from the attached market, and repaying debt.
     * @param amount Amount of DOLA to attempt to withdraw and burn, may be imprecise due to underlying contracts.
     * @dev May fail due to exceeding max loss parameters when withdrawing from lossy markets
     */
    function contraction(uint amount) onlyChair override external {
        (uint claimsUsed, uint dolaReceived) = _withdraw(amount);
        claims -= claimsUsed;
        _repayDebt(dolaReceived);
    }

    /**
     * @notice Function for turning all claims into DOLA, burning up to the debt, and sending the rest to gov.
     * @dev May fail due to exceeding max loss parameters when withdrawing from lossy markets
     */   
    function contractAll() onlyChair override external{
        (uint claimsUsed, uint dolaReceived) = _withdrawAll();
        claims -= claimsUsed;
        _repayDebt(dolaReceived);
    }

    /**
     * @notice Transfers DOLA to the lender contract, so it may be burnt
     * @param amount Amount of DOLA to transfer
     */
    function reclaim(uint amount) external {
        require(msg.sender == chair || msg.sender == lender || msg.sender == gov, "NOT CHAIR, LENDER OR GOV");
        DOLA.transfer(lender, amount);
        emit Reclaim(lender, amount);
    }

    // **********
    // * Events *
    // **********

    event NewLender(address newLender);
    event Reclaim(address lender, uint amount);
}
