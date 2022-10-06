// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../velo-fed/VeloFarmerMessenger.sol";

contract VeloFarmerMessengerTest is Test {
    VeloFarmerMessenger messenger;

    address gov = address(0xA);
    address chair = address(0xB);
    address user = address(0xC);
    address veloFedPlaceholder = address(0xD);

    error OnlyGov();
    error OnlyChair();

    function setUp() public {
        messenger = new VeloFarmerMessenger(gov, chair, veloFedPlaceholder);
    }

    function test_setPendingGovFunction_fails_whenCalledByNonGov() public {
        vm.startPrank(user);
        vm.expectRevert(OnlyGov.selector);
        messenger.setPendingMessengerGov(user);
    }

    function test_onlyChairFunction_fails_whenCalledByNonChair() public {
        vm.startPrank(user);
        vm.expectRevert(OnlyChair.selector);
        messenger.claimVeloRewards();
    }
}