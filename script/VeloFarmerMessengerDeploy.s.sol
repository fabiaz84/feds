// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/velo-fed/VeloFarmerMessenger.sol";

contract VeloFarmerMessengerDeploy is Script {
    address chair = 0x8F97cCA30Dbe80e7a8B462F1dD1a51C32accDfC8;
    address gov = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;
    address guardian = 0xE3eD95e130ad9E15643f5A5f232a3daE980784cd;
    address veloFarmer = address(0);

    VeloFarmerMessenger veloFarmerMessenger;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        veloFarmerMessenger = new VeloFarmerMessenger(gov, chair, guardian, veloFarmer);

        vm.stopBroadcast();
    }
}
