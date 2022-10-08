// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/velo-fed/VeloFarmer.sol";

contract VeloFarmerDeploy is Script {
    address chair = address(0); //VeloFarmerMessengerAddress
    address gov = address(0); //VeloFarmerMessengerAddress
    address treasury = 0xa283139017a2f5BAdE8d8e25412C600055D318F8;
    address guardian = address(0); //VeloFarmerMessengerAddress
    address optiFed = address(0);

    address payable router = payable(0xa132DAB612dB5cB9fC9Ac426A0Cc215A3423F9c9);
    address DOLA = 0x8aE125E8653821E851F12A49F7765db9a9ce7384;
    address USDC = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
    address public l2optiBridgeAddress = 0x4200000000000000000000000000000000000010;

    uint maxSlippageBpsDolaToUsdc = 100;
    uint maxSlippageBpsUsdcToDola = 20;
    uint maxSlippageBpsLiquidity = 20;

    VeloFarmer veloFarmer;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        veloFarmer = new VeloFarmer(router, DOLA, USDC, gov, chair, treasury, guardian, l2optiBridgeAddress, optiFed, maxSlippageBpsDolaToUsdc, maxSlippageBpsUsdcToDola, maxSlippageBpsLiquidity);

        vm.stopBroadcast();
    }
}
