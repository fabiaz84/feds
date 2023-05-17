// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "ds-test/test.sol";
import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IDola} from "src/interfaces/velo/IDola.sol";
import {ArbiGovMessengerL1} from "src/arbi-fed/ArbiGovMessengerL1.sol";
import {AuraFarmer} from "src/arbi-fed/AuraFarmer.sol";
import {IInbox} from "arbitrum-nitro/contracts/src/bridge/IInbox.sol";
import {GovernorL2} from "src/l2-gov/GovernorL2.sol";
import {AddressAliasHelper} from "src/utils/AddressAliasHelper.sol";

contract AuraFarmerMock {
    address public l2Chair;
    address public l2Gov;

    error OnlyL2Gov();

    constructor(){
        l2Gov = msg.sender;
    }

    function changeL2Chair(address newChair) external {
        if (msg.sender != l2Gov) revert OnlyL2Gov();
        l2Chair = newChair;
    }
}

contract GovernorMainnetTest is Test {
    GovernorL2 governor;
    AuraFarmerMock auraFarmerMock;
    
    address gov = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;

    //Feds
    ArbiGovMessengerL1 messenger;
    address l2MessengerAlias;
    
    error OnlyGov();
    error OnlyChair();
    error DeltaAboveMax();
    error ExecutionNotAuthorized();

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 17228840); 

        vm.warp(block.timestamp + 1 days);

        messenger = new ArbiGovMessengerL1(gov);
        
        l2MessengerAlias = AddressAliasHelper.applyL1ToL2Alias(address(messenger));

        governor = new GovernorL2(address(messenger));

        vm.prank(address(governor));
        auraFarmerMock = new AuraFarmerMock();

        assertEq(auraFarmerMock.l2Gov(), address(governor));
    }


    function test_execute() public {
        address newChair = address(0x70);

        bytes memory data = abi.encodeWithSelector(AuraFarmerMock.changeL2Chair.selector, newChair);
        assertEq(address(auraFarmerMock.l2Chair()), address(0));

        vm.prank(l2MessengerAlias);
        governor.execute(address(auraFarmerMock), data);

        assertEq(address(auraFarmerMock.l2Chair()), newChair);
    }

    function test_setPermission() public {
        assertEq(governor.getPermission(address(this), address(auraFarmerMock), AuraFarmerMock.changeL2Chair.selector), false);

        vm.prank(l2MessengerAlias);
        governor.setPermission(address(this), address(auraFarmerMock),  AuraFarmerMock.changeL2Chair.selector, true);

        assertEq(governor.getPermission(address(this), address(auraFarmerMock), AuraFarmerMock.changeL2Chair.selector), true);

        assertEq(address(auraFarmerMock.l2Chair()), address(0));
        
        address newChair = address(0x70);
        bytes memory data = abi.encodeWithSelector(AuraFarmerMock.changeL2Chair.selector, newChair);

        governor.execute(address(auraFarmerMock), data);

        assertEq(address(auraFarmerMock.l2Chair()), newChair);
    }
    
   
}
