// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "ds-test/test.sol";
import "forge-std/Test.sol";
import { IERC20 } from "../interfaces/IERC20.sol";
import { IDola } from "../interfaces/velo/IDola.sol";
import "../velo-fed/VeloFarmer.sol";
import {OptiFed} from "../velo-fed/OptiFed.sol";

contract OptiFedMainnetTest is Test {
    //Tokens
    IDola public DOLA = IDola(0x865377367054516e17014CcdED1e7d814EDC9ce4);
    IERC20 public USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address public optiFedAddress = address(0xA);

    address l1optiBridgeAddress = 0x99C9fc46f92E8a1c0deC1b1747d010903E884bE1;

    //EOAs
    address user = address(0x69);
    address chair = address(0xB);
    address gov = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;

    //Numbas
    uint dolaAmount = 100_000e18;
    uint usdcAmount = 100_000e6;

    //Feds
    OptiFed fed;

    error OnlyGov();
    error OnlyChair();
    
    function setUp() public {
        vm.startPrank(chair);

        fed = new OptiFed(gov, address(0x69), 1_000_000e18);

        vm.stopPrank();
        vm.startPrank(gov);

        fed.setMaxSlippageDolaToUsdc(500);
        fed.setMaxSlippageUsdcToDola(100);
        DOLA.addMinter(address(fed));

        vm.stopPrank();
    }

    function testL1_OptiFedExpansion() public {
        vm.startPrank(chair);

        uint prevBal = DOLA.balanceOf(l1optiBridgeAddress);

        fed.expansion(dolaAmount);

        assertEq(prevBal + dolaAmount, DOLA.balanceOf(l1optiBridgeAddress));
    }

    function testL1_OptiFedExpansionAndSwap() public {
        vm.startPrank(chair);

        uint prevBal = DOLA.balanceOf(l1optiBridgeAddress);

        fed.expansionAndSwap(dolaAmount);

        assertEq(prevBal + dolaAmount / 2, DOLA.balanceOf(l1optiBridgeAddress));
    }

    function testL1_changeVeloFarmer_fail_whenCalledByNonGov() public {
        vm.startPrank(chair);

        vm.expectRevert(OnlyGov.selector);
        fed.changeVeloFarmer(user);
    }

    function testL1_changeChair_fail_whenCalledByNonGov() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyGov.selector);
        fed.changeChair(user);
    }

    function testL1_changeGov_fail_whenCalledByNonGov() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyGov.selector);
        fed.changeGov(user);
    }

    function testL1_setMaxDailyDelta_fail_whenCalledByNonGov() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyGov.selector);
        fed.setMaxDailyDelta(1e18);
    }
    
    function testL1_setMaxSlippageDolaToUsdc_fail_whenCalledByNonGov() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyGov.selector);
        fed.setMaxSlippageDolaToUsdc(500);
    }

    function testL1_setMaxSlippageUsdcToDola_fail_whenCalledByNonGov() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyGov.selector);
        fed.setMaxSlippageUsdcToDola(500);
    }

    function testL1_resign_fail_whenCalledByNonChair() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyChair.selector);
        fed.resign();
    }

    function testL1_swapDOLAtoUSDC_fail_whenCalledByNonChair() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyChair.selector);
        fed.swapDOLAtoUSDC(1e18);
    }

    function testL1_swapUSDCtoDOLA_fail_whenCalledByNonChair() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyChair.selector);
        fed.swapUSDCtoDOLA(1e6);
    }

    function testL1_contractAll_fail_whenCalledByNonChair() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyChair.selector);
        fed.contractAll();
    }

    function testL1_contract_fail_whenCalledByNonChair() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyChair.selector);
        fed.contraction(1e18);
    }

    //My loyal helpers

    function gibDOLA(address _user, uint _amount) internal {
        bytes32 slot;
        assembly {
            mstore(0, _user)
            mstore(0x20, 0x0)
            slot := keccak256(0, 0x40)
        }

        vm.store(address(DOLA), slot, bytes32(_amount));
    }

    function gibUSDC(address _user, uint _amount) internal {
        bytes32 slot;
        assembly {
            mstore(0, _user)
            mstore(0x20, 0x0)
            slot := keccak256(0, 0x40)
        }

        vm.store(address(USDC), slot, bytes32(_amount));
    }

    function gibToken(address _token, address _user, uint _amount) public {
        bytes32 slot;
        assembly {
            mstore(0, _user)
            mstore(0x20, 0x0)
            slot := keccak256(0, 0x40)
        }

        vm.store(_token, slot, bytes32(uint256(_amount)));
    }
}
