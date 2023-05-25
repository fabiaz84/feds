pragma solidity ^0.8.13;
import "src/interfaces/IERC20.sol";

abstract contract BaseFed {
    //Mintable DOLA contract
    IERC20 public immutable DOLA;
    //Amount of DOLA the contract has minted
    uint public debt;
    //Amount of claims the contract has on underlying markets
    uint public claims;
    //Treasury of Inverse Finance DAO
    address public gov;
    //Pending change of the governance role
    address public pendingGov;
    //Chair address allowed to perform expansions and contractions
    address public chair;

    constructor(address _DOLA, address _gov, address _chair){
        require(gov != address(0), "Gov set to 0");
        require(_DOLA != address(0), "Must be correct DOLA address");
        require(block.chainid == 1, "Must mint DOLA on Mainnet");
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
    function takeProfit(uint flag) external virtual;

    /**
     * @notice Function for withdrawing underlying of Fed in emergency.
       Can be useful in case of Fed accounting errors, hacks of underlying market or accidents.
     * @dev Will likely destroy all contract accounting. Use carefully. Should send withdrawn tokens to gov.
     */
    function emergencyWithdraw() onlyGov external virtual{
        revert("NOT IMPLEMENTED");
    }

    // **********************
    // * Standard Functions *
    // **********************

    /**
     * @notice Function for withdrawing stuck tokens of Fed in emergency.
       Can be useful in case of Fed accounting errors, hacks of underlying market or accidents.
     * @dev May destroy all accounting if used on DOLA or claims. Use carefully.
     * @param token Token to sweep balance of to governance
     */
    function sweep(address token) onlyGov external {
        IERC20(token).transfer(gov, IERC20(token).balanceOf(address(this)));
    }

    /**
     * @notice Internal function for paying down debt. Should be used in all functions that pay down DOLA debt,
     like contraction, contractAll and repayDebt.
     * @dev Will send any surplus DOLA to gov.
     * @dev Used by repayDebt, contraction and contractAll functions
     * @param amount Amount of debt to repay.
     */
    function _repayDebt(uint amount) internal {
        if(amount > debt){
            uint sendAmount = amount - debt;
            uint burnAmount = debt;
            debt = 0;
            DOLA.burn(burnAmount);
            DOLA.transfer(gov, sendAmount);
            emit Profit(address(DOLA), sendAmount);
            emit Contraction(burnAmount);
        } else {
            debt -= amount;
            DOLA.burn(amount);
            emit Contraction(amount);
        }
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
     * @notice Function for expanding DOLA into a given fed market.
     * @param amount Amount of DOLA to mint and expand into the fed.
     * @dev May fail due to exceeding max loss parameters when depositing to lossy markets
     */
    function expansion(uint amount) onlyChair external {
        debt += amount;
        DOLA.mint(address(this), amount);
        claims += _deposit(amount);
        emit Expansion(amount);
    }

    /**
     * @notice Function for contracting DOLA from the attached market, and repaying debt.
     * @param amount Amount of DOLA to attempt to withdraw and burn, may be imprecise due to underlying contracts.
     * @dev May fail due to exceeding max loss parameters when withdrawing from lossy markets
     */
    function contraction(uint amount) onlyChair external {
        (uint claimsUsed, uint dolaReceived) = _withdraw(amount);
        claims -= claimsUsed;
        _repayDebt(dolaReceived);
    }

    /**
     * @notice Function for turning all claims into DOLA, burning up to the debt, and sending the rest to gov.
     * @dev May fail due to exceeding max loss parameters when withdrawing from lossy markets
     */   
    function contractAll() onlyChair external virtual{
        (uint claimsUsed, uint dolaReceived) = _withdrawAll();
        claims -= claimsUsed;
        _repayDebt(dolaReceived);
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
