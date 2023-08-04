pragma solidity ^0.8.13;

import {IL1GatewayRouter} from "arbitrum/tokenbridge/ethereum/gateway/IL1GatewayRouter.sol";
import {IInbox} from "arbitrum-nitro/contracts/src/bridge/IInbox.sol";

contract ArbiGovMessengerL1 {
    error OnlyGov();
    error OnlyAllowed();
    error OnlyPendingGov();

    IL1GatewayRouter public immutable gatewayRouter = IL1GatewayRouter(0x72Ce9c846789fdB6fC1f34aC4AD25Dd9ef7031ef); 
    
    address public gov;
    address public pendingGov;
    mapping(address => bool) public allowList;

    struct L2GasParams {
        uint256 _maxSubmissionCost;
        uint256 _maxGas;
        uint256 _gasPriceBid;
    }

    event MessageSent(address to, bytes data);

    constructor (address gov_) {
        gov = gov_;
    }

    modifier onlyGov {
         if (msg.sender != gov) revert OnlyGov();
        _;   
    }

    modifier onlyAllowed {
        if (msg.sender != gov && !allowList[msg.sender]) revert OnlyAllowed();
        _;
    }
    
    function sendMessage(
        address _inbox,
        address _to,
        address _refundTo,
        address _user,
        uint256 _l1CallValue,
        uint256 _l2CallValue,
        L2GasParams memory _l2GasParams,
        bytes memory _data
    ) external payable onlyAllowed() returns (uint256) {
        
        emit MessageSent(_to, _data);

        return IInbox(_inbox).createRetryableTicket{ value: _l1CallValue }(
            _to,
            _l2CallValue,
            _l2GasParams._maxSubmissionCost,
            _refundTo, // only refund excess fee to the custom address
            _user, // user can cancel the retryable and receive call value refund
            _l2GasParams._maxGas,
            _l2GasParams._gasPriceBid,
            _data
        );
    }

    function depositEth(
        address _inbox
    ) external payable onlyGov() returns (uint256) {

        return IInbox(_inbox).depositEth{ value: msg.value }();
    }

    function setPendingGov(address newPendingGov) external onlyGov {
        pendingGov = newPendingGov;
    }

    function claimGov() external { 
        if(msg.sender != pendingGov) revert OnlyPendingGov();
        gov = pendingGov;
        pendingGov = address(0);
    }

    function setAllowed(address allowee, bool isAllowed) external onlyGov {
        allowList[allowee] = isAllowed;
    }
}
