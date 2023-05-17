// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.4;

import {ERC1155Holder} from "lib/openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ERC721Holder} from "lib/openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {AddressAliasHelper} from "src/utils/AddressAliasHelper.sol";

// Generic implementation of a governor contract that can execute arbitrary calls on L2.
// The contract is owned by the L1 Gov Messenger, which is controlled by the governance on L1
// This contract can also execute calls by callers who had previous authorization from the L1 Gov Messenger

contract GovernorL2 is ERC1155Holder, ERC721Holder {
    
    /// @notice Emitted when the caller is not the owner.
    error ExecutionNotAuthorized(
        address owner,
        address caller,
        address callerL1,
        address target,
        bytes4 selector
    );

    /// @notice Emitted when execution reverted with no reason.
    error ExecutionReverted();

    /// @notice Emitted when the caller is not the owner.
    error NotOwner(address owner, address caller);

    /// @notice Emitted when the owner is changed during the DELEGATECALL.
    error OwnerChanged(address originalOwner, address newOwner);

    /// @notice Emitted when passing an EOA or an undeployed contract as the target.
    error TargetInvalid(address target);

    // TODO: should we add some timelock mechanism for updating the gov address?

    /// PUBLIC STORAGE ///

    address public govMessenger;

    uint256 public minGasReserve;

    /// INTERNAL STORAGE ///

    /// @notice Maps envoys to target contracts to function selectors to boolean flags.
    mapping(address => mapping(address => mapping(bytes4 => bool)))
        internal permissions;

    /// EVENTS ///

    event Execute(address indexed target, bytes data, bytes response);

    event TransferOwnership(address indexed oldOwner, address indexed newOwner);

    /// CONSTRUCTOR ///

    constructor(address govMessenger_) {
        minGasReserve = 5_000;
        govMessenger = govMessenger_;
        emit TransferOwnership(address(0), govMessenger_);
    }

    modifier onlyGov() {
        address callerL1 = AddressAliasHelper.undoL1ToL2Alias(msg.sender);
        if (govMessenger != callerL1) revert NotOwner(govMessenger, callerL1);
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
        address target,
        bytes calldata data
    )
        external
        payable
        checkPermission(target, data)
        returns (bytes memory response)
    {
        // Check that the target is a valid contract.
        if (target.code.length == 0) {
            revert TargetInvalid(target);
        }

        // Reserve some gas to ensure that the function has enough to finish the execution.
        uint256 stipend = gasleft() - minGasReserve;

        // Call to the target contract.
        bool success;
        (success, response) = target.call{gas: stipend}(data);

        // Log the execution.
        emit Execute(target, data, response);

        // Check if the call was successful or not.
        if (!success) {
            // If there is return data, the call reverted with a reason or a custom error.
            if (response.length > 0) {
                assembly {
                    let returndata_size := mload(response)
                    revert(add(32, response), returndata_size)
                }
            } else {
                revert ExecutionReverted();
            }
        }
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
        address oldGovMessenger = govMessenger;
        govMessenger = newGovMessenger;
        emit TransferOwnership(oldGovMessenger, newGovMessenger);
    }

    /// VIEW FUNCTIONS ///

    function getPermission(
        address envoy,
        address target,
        bytes4 selector
    ) external view returns (bool) {
        return permissions[envoy][target][selector];
    }

    /// FALLBACK FUNCTION ///

    /// @dev Called when Ether is sent and the call data is empty.
    receive() external payable {}
}
