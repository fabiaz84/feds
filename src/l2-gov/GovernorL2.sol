// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {Create2} from "lib/openzeppelin/contracts/utils/Create2.sol";
import {Address} from "lib/openzeppelin/contracts/utils/Address.sol";
import {BytesLib} from "src/utils/BytesLib.sol";
import {AddressAliasHelper} from "src/utils/AddressAliasHelper.sol";

contract GovernorL2 {
    
    error InsufficientBalance(uint256 balance, uint256 value);

    error UnknownOperationType(uint256 operationTypeProvided);

    error MsgValueDisallowedInStaticCall();

    error MsgValueDisallowedInDelegateCall();

    error CreateOperationsRequireEmptyRecipientAddress();

    error ContractDeploymentFailed();

    error NoContractBytecodeProvided();

    error ExecuteParametersLengthMismatch();

    error ExecuteParametersEmptyArray();

    error OwnerChanged(address newOwner, address oldOwner);

    error OnlyGov();

    error ExecutionNotAuthorized(
        address owner,
        address caller,
        address callerL1,
        address target,
        bytes4 selector
    );

    // OPERATION TYPES
    uint256 constant OPERATION_0_CALL = 0;
    uint256 constant OPERATION_1_CREATE = 1;
    uint256 constant OPERATION_2_CREATE2 = 2;
    uint256 constant OPERATION_3_STATICCALL = 3;
    uint256 constant OPERATION_4_DELEGATECALL = 4;

    address public govMessenger;

    /// @notice Maps envoys to target contracts to function selectors to boolean flags.
    mapping(address => mapping(address => mapping(bytes4 => bool)))
        internal permissions;

    /**
     * @notice Emitted when deploying a contract
     * @param operationType The opcode used to deploy the contract (CREATE or CREATE2)
     * @param contractAddress The created contract address
     * @param value The amount of native tokens (in Wei) sent to fund the created contract address
     */
    event ContractCreated(
        uint256 indexed operationType,
        address indexed contractAddress,
        uint256 indexed value,
        bytes32 salt
    );

    /**
     * @notice Emitted when calling an address (EOA or contract)
     * @param operationType The low-level call opcode used to call the `to` address (CALL, STATICALL or DELEGATECALL)
     * @param target The address to call. `target` will be unused if a contract is created (operation types 1 and 2).
     * @param value The amount of native tokens transferred with the call (in Wei)
     * @param selector The first 4 bytes (= function selector) of the data sent with the call
     */
    event Executed(
        uint256 indexed operationType,
        address indexed target,
        uint256 indexed value,
        bytes4 selector
    );

    event TransferOwnership(address indexed oldOwner, address indexed newOwner);

    constructor(address govMessenger_) {
        govMessenger = govMessenger_;
    }

    modifier onlyGov() {
        address callerL1 = AddressAliasHelper.undoL1ToL2Alias(msg.sender);
        if (govMessenger != callerL1) revert OnlyGov();
        _;
    }

    modifier checkPermission(address target, bytes calldata data) {
        address callerL1 = AddressAliasHelper.undoL1ToL2Alias(msg.sender);
        if (govMessenger != callerL1) {
            bytes4 selector;
            assembly {
                selector := calldataload(data.offset)
            }
            if (!permissions[msg.sender][target][selector]) {
                revert ExecutionNotAuthorized(
                    govMessenger,
                    msg.sender,
                    callerL1,
                    target,
                    selector
                );
            }
        }
        _;
    }

    function execute(
        uint256 operationType,
        address target,
        uint256 value,
        bytes calldata data
    ) public payable returns (bytes memory) {
        return _execute(operationType, target, value, data);
    }

    function executeBatch(
        uint256[] calldata operationsType,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata datas
    ) public payable returns (bytes[] memory) {
        return _executeBatch(operationsType, targets, values, datas);
    }

    function setPermission(
        address envoy,
        address target,
        bytes4 selector,
        bool permission
    ) external onlyGov {
        permissions[envoy][target][selector] = permission;
    }

    function transferOwnership(address newGovMessenger) external onlyGov {
        govMessenger = newGovMessenger;
        emit TransferOwnership(govMessenger, newGovMessenger);
    }

    /**
     * @dev check the `operationType` provided and perform the associated low-level opcode.
     * see `IERC725X.execute(uint256,address,uint256,bytes)`.
     */
    function _execute(
        uint256 operationType,
        address target,
        uint256 value,
        bytes calldata data
    ) internal checkPermission(target, data) returns (bytes memory) {
        // CALL
        if (operationType == OPERATION_0_CALL) {
            return _executeCall(target, value, data);
        }

        // Deploy with CREATE
        if (operationType == OPERATION_1_CREATE) {
            if (target != address(0))
                revert CreateOperationsRequireEmptyRecipientAddress();
            return _deployCreate(value, data);
        }

        // Deploy with CREATE2
        if (operationType == OPERATION_2_CREATE2) {
            if (target != address(0))
                revert CreateOperationsRequireEmptyRecipientAddress();
            return _deployCreate2(value, data);
        }

        // STATICCALL
        if (operationType == OPERATION_3_STATICCALL) {
            if (value != 0) revert MsgValueDisallowedInStaticCall();
            return _executeStaticCall(target, data);
        }

        // DELEGATECALL
        //
        // WARNING! delegatecall is a dangerous operation type! use with EXTRA CAUTION
        //
        // delegate allows to call another deployed contract and use its functions
        // to update the state of the current calling contract.
        //
        // this can lead to unexpected behaviour on the contract storage, such as:
        // - updating any state variables (even if these are protected)
        // - update the contract owner
        // - run selfdestruct in the context of this contract
        //
        if (operationType == OPERATION_4_DELEGATECALL) {
            if (value != 0) revert MsgValueDisallowedInDelegateCall();
            return _executeDelegateCall(target, data);
        }

        revert UnknownOperationType(operationType);
    }

    /**
     * @dev same as `_execute` but for batch execution
     * see `IERC725X,execute(uint256[],address[],uint256[],bytes[])`
     */
    function _executeBatch(
        uint256[] calldata operationsType,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata datas
    ) internal returns (bytes[] memory) {
        if (
            operationsType.length != targets.length ||
            (targets.length != values.length || values.length != datas.length)
        ) {
            revert ExecuteParametersLengthMismatch();
        }

        if (operationsType.length == 0) {
            revert ExecuteParametersEmptyArray();
        }

        bytes[] memory result = new bytes[](operationsType.length);

        for (uint256 i = 0; i < operationsType.length; ) {
            result[i] = _execute(
                operationsType[i],
                targets[i],
                values[i],
                datas[i]
            );

            // Increment the iterator in unchecked block to save gas
            unchecked {
                ++i;
            }
        }

        return result;
    }

    /**
     * @dev perform low-level call (operation type = 0)
     * @param target The address on which call is executed
     * @param value The value to be sent with the call
     * @param data The data to be sent with the call
     * @return result The data from the call
     */
    function _executeCall(
        address target,
        uint256 value,
        bytes memory data
    ) internal returns (bytes memory result) {
        if (address(this).balance < value) {
            revert InsufficientBalance(address(this).balance, value);
        }

        emit Executed(OPERATION_0_CALL, target, value, bytes4(data));

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returnData) = target.call{value: value}(
            data
        );
        result = Address.verifyCallResult(success, returnData, "Unknown Error");
    }

    /**
     * @dev perform low-level staticcall (operation type = 3)
     * @param target The address on which staticcall is executed
     * @param data The data to be sent with the staticcall
     * @return result The data returned from the staticcall
     */
    function _executeStaticCall(
        address target,
        bytes memory data
    ) internal returns (bytes memory result) {
        emit Executed(OPERATION_3_STATICCALL, target, 0, bytes4(data));

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returnData) = target.staticcall(data);
        result = Address.verifyCallResult(success, returnData, "Unknown Error");
    }

    /**
     * @dev perform low-level delegatecall (operation type = 4)
     * @param target The address on which delegatecall is executed
     * @param data The data to be sent with the delegatecall
     * @return result The data returned from the delegatecall
     */
    function _executeDelegateCall(
        address target,
        bytes memory data
    ) internal returns (bytes memory result) {
        emit Executed(OPERATION_4_DELEGATECALL, target, 0, bytes4(data));

        // Save the owner address in memory. This local variable cannot be modified during the DELEGATECALL.
        address gov_ = govMessenger;

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returnData) = target.delegatecall(data);

        if (gov_ != govMessenger) {
            revert OwnerChanged(gov_, govMessenger);
        }

        result = Address.verifyCallResult(success, returnData, "Unknown Error");
    }

    /**
     * @dev deploy a contract using the CREATE opcode (operation type = 1)
     * @param value The value to be sent to the contract created
     * @param creationCode The contract creation bytecode to deploy appended with the constructor argument(s)
     * @return newContract The address of the contract created as bytes
     */
    function _deployCreate(
        uint256 value,
        bytes memory creationCode
    ) internal returns (bytes memory newContract) {
        if (address(this).balance < value) {
            revert InsufficientBalance(address(this).balance, value);
        }

        if (creationCode.length == 0) {
            revert NoContractBytecodeProvided();
        }

        address contractAddress;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            contractAddress := create(
                value,
                add(creationCode, 0x20),
                mload(creationCode)
            )
        }

        if (contractAddress == address(0)) {
            revert ContractDeploymentFailed();
        }

        newContract = abi.encodePacked(contractAddress);
        emit ContractCreated(
            OPERATION_1_CREATE,
            contractAddress,
            value,
            bytes32(0)
        );
    }

    /**
     * @dev deploy a contract using the CREATE2 opcode (operation type = 2)
     * @param value The value to be sent to the contract created
     * @param creationCode The contract creation bytecode to deploy appended with the constructor argument(s) and a bytes32 salt
     * @return newContract The address of the contract created as bytes
     */
    function _deployCreate2(
        uint256 value,
        bytes memory creationCode
    ) internal virtual returns (bytes memory newContract) {
        if (creationCode.length == 0) {
            revert NoContractBytecodeProvided();
        }

        bytes32 salt = BytesLib.toBytes32(
            creationCode,
            creationCode.length - 32
        );
        bytes memory bytecode = BytesLib.slice(
            creationCode,
            0,
            creationCode.length - 32
        );
        address contractAddress = Create2.deploy(value, salt, bytecode);

        newContract = abi.encodePacked(contractAddress);
        emit ContractCreated(OPERATION_2_CREATE2, contractAddress, value, salt);
    }
}
