pragma solidity ^0.8.13;

import {IL1GatewayRouter} from "arbitrum/tokenbridge/ethereum/gateway/IL1GatewayRouter.sol";
import {IInbox} from "arbitrum-nitro/contracts/src/bridge/IInbox.sol";

contract ArbiGovMessengerL1 {

    // TODO: add chair
    error OnlyGov();

    IL1GatewayRouter public immutable gatewayRouter = IL1GatewayRouter(0x72Ce9c846789fdB6fC1f34aC4AD25Dd9ef7031ef); 
    
    address public gov;

    struct L2GasParams {
        uint256 _maxSubmissionCost;
        uint256 _maxGas;
        uint256 _gasPriceBid;
    }


    constructor (address gov_) {
        gov = gov_;
    }

    modifier onlyGov {
        if (msg.sender != gov) revert OnlyGov();
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
    ) external onlyGov() returns (uint256) {
        
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

    
}