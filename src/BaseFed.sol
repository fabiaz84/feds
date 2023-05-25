pragma solidity ^0.8.13;
import "src/interfaces/IERC20.sol";

abstract contract BaseFed {
    IERC20 public immutable DOLA;
    uint public debt;
    address public gov;
    address public pendingGov;
    address public chair;

    constructor(address _DOLA, address _gov, address _chair){
        require(gov != address(0), "Gov set to 0");
        require(_DOLA != address(0), "Must be correct DOLA address");
        gov = _gov;
        chair = _chair;
        DOLA = IERC20(_DOLA);
    }

    // ******************
    // * Access Control *
    // ******************

    modifier onlyGov(){
        require(msg.sender == gov, "NOT GOV");
        _;
    }

    modifier onlyChair(){
        require(msg.sender == chair || msg.sender == gov, "NOT PERMISSIONED");
        _;
    }

    /**
     * @notice Sets the pendingGov, which can claim gov role.
     * @dev Only callable by gov
     */
    function setPendingGov(address _pendingGov) onlyGov external {
        pendingGov = _pendingGov;
        emit NewPendingGov(_pendingGov);
    }

    /**
     * @notice Claims the gov role
     * @dev Only callable by pendingGov
     */
    function claimPendingGov() external {
        require(msg.sender == pendingGov, "NOT PENDING GOV");
        gov = pendingGov;
        pendingGov = address(0);
        emit NewGov(gov);
    }

    /**
     * @notice Sets the chair of the Fed
     * @dev Only callable by gov
     */
    function setChair(address newChair) onlyGov external{
        chair = newChair;
        emit NewChair(newChair);
    }

    /**
     * @notice Resigns from the Fed role
     * @dev Useful in case of key compromise or multi-sig compromise
     */
    function resign() onlyChair external{
        chair = address(0);
    }

    // **********************
    // * Abstract Functions *
    // **********************

    /**
     * @notice Function for minting DOLA and expanding it into a given fed market.
     * @dev Must increase DOLA debt of fed.
     * @dev Must emit an expansion event.
     * @dev If Fed is attached to an AMM or other contract that may incur a loss on expansion,
       a mechanism for limiting this loss must exist in the contract.
     * @param amount Amount of DOLA to mint and expand into the fed.
     */
    function expansion(uint amount) onlyChair external virtual{
        revert("NOT IMPLEMENTED");
    }

    /**
     * @notice Function for contracting DOLA from the attached market, and repaying debt.
     * @dev Must decrease DOLA debt of fed.
     * @dev Must emit a contraction event.
     * @dev If Fed is attached to an AMM or other contract that may incur a loss on withdrawal,
       a mechanism for limiting this loss must exist in the contract.
     * @dev If contraction yields more DOLA than debt, surplus should be sent to governance treasury.
     * @param amount Amount of DOLA to attempt to withdraw and burn, may be imprecise due to underlying contract.
     */
    function contraction(uint amount) onlyChair external virtual{
        revert("NOT IMPLEMENTED");
    }

    /**
     * @notice Function for turning all underlying receipts into DOLA, and burning it.
     * @dev Must decrease DOLA debt of fed.
     * @dev Must emit a contraction event.
     * @dev If Fed is attached to an AMM or other contract that may incur a loss on withdrawal,
       a mechanism for limiting this loss must exist in the contract.
     * @dev If contraction yields more DOLA than debt, surplus should be sent to governance treasury.
       Use _repayDebt function for this.
     */   
    function contractAll() onlyChair external virtual{
        revert("NOT IMPLEMENTED");
    }
    /**
     * @notice Funtion for taking profit from profit generating feds.
     * @dev Must attempt to not take excessive profit
     * @dev Must NOT reduce debt
     * @dev Profits must be sent to governance
     * @param flag Flag for signalling certain profit taking behaviour.
       Some profit taking may be unsafe and should be permissioned to only chair,
       while other profit taking may be safe for all to call.
     */
    function takeProfit(uint flag) external virtual;

    // **********************
    // * Standard Functions *
    // **********************

    /**
     * @notice Function for withdrawing stuck tokens of Fed in emergency.
       Can be useful in case of Fed accounting errors, hacks of underlying market or accidents.
     * @dev May destroy all accounting if used on DOLA or underlying. Use carefully.
     * @param token Token to sweep balance of to governance
     */
    function sweep(address token) onlyGov external {
        IERC20(token).transfer(IERC20(token).balanceOf(address(this)), gov);
    }

    /**
     * @notice Accounting function for repaying any debt that the contract will be unable to repay itself.
     * @param amount Amount of debt to repay.
     */
    function repayDebt(uint amount) external {
        require(amount <= debt, "BURN HIGHER THAN DEBT");
        DOLA.transferFrom(msg.sender, address(this), amount);
        _repayDebt(amount);
    }

    /**
     * @notice Internal function for paying down debt. Should be used in all functions that pay down DOLA debt,
     like contraction, contractAll and repayDebt.
     * @dev Will send any surplus DOLA to gov.
     * @param amount Amount of debt to repay.
     */
    function _repayDebt(uint amount) internal {
        if(amount > debt){
            uint sendAmount = amount - debt;
            uint burnAmount = debt;
            debt = 0;
            DOLA.burn(burnAmount);
            sendAmount += DOLA.balanceOf(address(this));
            DOLA.transfer(gov, sendAmount);
            emit Profit(address(DOLA), sendAmount);
            emit Contraction(burnAmount);
        } else {
            debt -= amount;
            DOLA.burn(amount);
            emit Contraction(amount);
        }
    }

    // **********
    // * Events *
    // **********

    event NewChair(address newChair);
    event NewPendingGov(address newPendingGov);
    event NewGov(address newGov);
    event Expansion(uint amount);
    event Contraction(uint amount);
    event Profit(address token, uint amount);
}
