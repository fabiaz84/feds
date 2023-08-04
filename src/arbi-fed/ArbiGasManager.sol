pragma solidity ^0.8.13;

contract ArbiGasManager {
    address public gov;
    address public gasClerk;
    address public refundAddress;
    address public pendingGov;
    uint public gasLimit;
    uint public maxSubmissionCostCeiling;
    uint public maxSubmissionCost;
    uint public gasPriceCeiling;
    uint public gasPrice;

    constructor(address _gov, address _gasClerk){
        gov = _gov;
        gasClerk = _gasClerk;
        maxSubmissionCost = 0.1 ether;
        gasPriceCeiling = 10**10; //10 gWEI
    }

    error OnlyGov();
    error OnlyGasClerk();
    error OnlyPendingGov();
    error MaxSubmissionCostAboveCeiling();
    error GasPriceAboveCeiling();

    modifier onlyGov() {
        if(msg.sender != gov) revert OnlyGov();
        _;
    }

    modifier onlyGasClerk(){
        if(msg.sender != gasClerk) revert OnlyGasClerk();
        _;
    }

    function setGasLimit(uint newGasLimit) external onlyGasClerk {
        gasLimit = newGasLimit; 
    }

    function setMaxSubmissionCost(uint newMaxSubmissionCost) external onlyGasClerk {
        if(newMaxSubmissionCost > maxSubmissionCostCeiling) revert MaxSubmissionCostAboveCeiling();
        maxSubmissionCost = newMaxSubmissionCost;
    }

    function setGasPrice(uint newGasPrice) external onlyGasClerk {
        if(newGasPrice > gasPriceCeiling) revert GasPriceAboveCeiling();
        gasPrice = newGasPrice;
    }

    function setRefundAddress(address newRefundAddress) external onlyGov {
        refundAddress = newRefundAddress;
    }

    function setSubmissionCostCeiling(uint newSubmissionCostCeiling) external onlyGov {
       maxSubmissionCostCeiling = newSubmissionCostCeiling; 
    }

    function setGasPriceCeiling(uint newGasPriceCeiling) external onlyGov {
       gasPriceCeiling = newGasPriceCeiling; 
    }

    function setGasClerk(address newGasClerk) external onlyGov {
        gasClerk = newGasClerk;
    }

    function setPendingGov(address newPendingGov) external onlyGov {
        pendingGov = newPendingGov;
    }

    function claimPendingGov() external {
        if(msg.sender != pendingGov) revert OnlyPendingGov();
        gov = pendingGov;
        pendingGov = address(0);
    }
}
