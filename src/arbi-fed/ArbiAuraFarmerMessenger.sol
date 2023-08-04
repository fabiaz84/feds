pragma solidity ^0.8.13;
import "src/arbi-fed/ArbiGasManager.sol";
import "src/arbi-fed/ArbiGovMessengerL1.sol";
import "src/arbi-fed/ArbiFed.sol";
import "src/arbi-fed/AuraFarmer.sol";


contract ArbiAuraFarmerMessenger is ArbiGasManager {
    
    ArbiGovMessengerL1 arbiGovMessenger;
    address auraFarmerL2;

    constructor(
        address _gov,
        address _gasClerk,
        address _arbiGovMessenger
    ) ArbiGasManager(_gov, _gasClerk) {
        arbiGovMessenger = ArbiGovMessengerL1(_arbiGovMessenger);
    }

    function _sendMessage(bytes memory _data) internal {

        ArbiGovMessengerL1.L2GasParams memory gasParams;
        gasParams._maxSubmissionCost = maxSubmissionCost;
        gasParams._maxGas = gasLimit;
        gasParams._gasPriceBid = gasPrice;
        arbiGovMessenger.sendMessage(
            auraFarmerL2,
            refundAddress,
            gasClerk,
            msg.value, //TODO: May not be right, do check
            0, //TODO: Find out what to put here
            gasParams,
            _data
        );
    }

    function changeL2Chair(address _newL2Chair) external onlyGov {
        bytes memory data = abi.encodeCall(AuraFarmer.changeL2Chair, _newL2Chair);
        _sendMessage(data);
    }

    function changeL2Guardian(address _newL2Guardian) external onlyGov {
        bytes memory data = abi.encodeCall(AuraFarmer.changeL2Guardian, _newL2Guardian);
        _sendMessage(data);
    }

    function changeL2TWG(address _newL2TWG) external onlyGov {
        bytes memory data = abi.encodeCall(AuraFarmer.changeL2TWG, _newL2TWG);
        _sendMessage(data);
    }

    function changeArbiFedL1(address _newArbiFedL1) external onlyGov {
        bytes memory data = abi.encodeCall(AuraFarmer.changeArbiFedL1, _newArbiFedL1);
        _sendMessage(data);
    }

    function changeArbiGovMessengerL1(address _newArbiGovMessengerL1) external onlyGov {
        bytes memory data = abi.encodeCall(AuraFarmer.changeArbiGovMessengerL1, _newArbiGovMessengerL1);
        _sendMessage(data);
    }

    function changeTreasuryL1(address _newTreasuryL1) external onlyGov {
        bytes memory data = abi.encodeCall(AuraFarmer.changeTreasuryL1, _newTreasuryL1);
        _sendMessage(data);
    }

    function setMaxLossSetableByGuardianBps(uint _newMaxLossSetableByGuardianBps) external onlyGov {
        bytes memory data = abi.encodeCall(AuraFarmer.setMaxLossSetableByGuardianBps, _newMaxLossSetableByGuardianBps);
        _sendMessage(data);
    }



    




}
