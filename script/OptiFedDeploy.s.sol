// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/velo-fed/OptiFed.sol";

contract OptiFedDeploy is Script {
    address chair = 0x8F97cCA30Dbe80e7a8B462F1dD1a51C32accDfC8;
    address gov = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;
    address veloFarmer = 0x9720d2FC06CB4C499a97AC6D0134132a766709c8;
    uint maxSlippageBpsDolaToUsdc = 25;
    uint maxSlippageBpsUsdcToDola = 10;

    OptiFed optiFed;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        optiFed = new OptiFed(gov, chair, veloFarmer, maxSlippageBpsDolaToUsdc, maxSlippageBpsUsdcToDola);

        vm.stopBroadcast();
    }
}
