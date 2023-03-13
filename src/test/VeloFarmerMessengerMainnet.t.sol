// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../velo-fed/VeloFarmerMessenger.sol";

contract VeloFarmerMessengerMainnetTest is Test {
    VeloFarmerMessenger messenger;

    address gov = address(0x926dF14a23BE491164dCF93f4c468A50ef659D5B);
    address chair = address(0xB);
    address user = address(0xC);
    address guardian = address(0xD);
    address veloFedPlaceholder = address(0xD);

    error OnlyGov();
    error OnlyChair();

    function setUp() public {
        messenger = VeloFarmerMessenger(0xFed673A89c1B661D9DCA1401FBf3B279DffEaBAe);
    }

    function test_setPendingGovFunction_fails_whenCalledByNonGov() public {
        vm.startPrank(user);
        vm.expectRevert(OnlyGov.selector);
        messenger.setPendingMessengerGov(user);
    }

    function test_setPendingGovFunction_succeeds_whenCalledByGov() public {
        vm.startPrank(gov);
        messenger.setPendingMessengerGov(user);
        vm.stopPrank();
    }

    function test_setPendingGovFunction_fails_whenCalledByGovTwoTimes() public {
        vm.startPrank(gov);
        messenger.setPendingMessengerGov(user);
        vm.expectRevert();
        messenger.setPendingMessengerGov(user);
        vm.stopPrank();
    }

    function test_onlyChairFunction_fails_whenCalledByNonChair() public {
        vm.startPrank(user);
        vm.expectRevert(OnlyChair.selector);
        messenger.claimVeloRewards();
    }
}
