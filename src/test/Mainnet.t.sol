// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "ds-test/test.sol";
import "forge-std/Vm.sol";
import { IERC20 } from "../interfaces/IERC20.sol";
import { IDola } from "../interfaces/IDola.sol";
import "../velo-fed/VeloFarmer.sol";
import {OptiFed} from "../velo-fed/OptiFed.sol";

contract VeloFedMainnetTest is DSTest {
    Vm internal constant vm = Vm(HEVM_ADDRESS);

    //Tokens
    IRouter public router = IRouter(payable(0xa132DAB612dB5cB9fC9Ac426A0Cc215A3423F9c9));
    IRewardsDistributor public rewards = IRewardsDistributor(0x5d5Bea9f0Fc13d967511668a60a3369fD53F784F);
    IGauge public dolaGauge = IGauge(0xAFD2c84b9d1cd50E7E18a55e419749A6c9055E1F);
    IDola public L2DOLA = IDola(0x8aE125E8653821E851F12A49F7765db9a9ce7384);
    IDola public L1DOLA = IDola(0x865377367054516e17014CcdED1e7d814EDC9ce4);
    IERC20 public VELO = IERC20(0x3c8B650257cFb5f272f799F5e2b4e65093a11a05);
    IERC20 public USDC = IERC20(0x7F5c764cBc14f9669B88837ca1490cCa17c31607);
    address public l2optiBridgeAddress = 0x4200000000000000000000000000000000000010;
    address public optiFedAddress = address(13);

    address l1optiBridgeAddress = 0x99C9fc46f92E8a1c0deC1b1747d010903E884bE1;

    //EOAs
    address user = address(69);
    address chair = address(1337);
    address gov = address(0x607);
    address l1gov = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;

    //Numbas
    uint dolaAmount = 100_000e18;
    uint usdcAmount = 100_000e6;

    //Feds
    VeloFarmer l2fed;
    OptiFed l1Fed;

    error OnlyGov();
    error OnlyChair();
    
    function setUp() public {
        vm.startPrank(chair);

        if (block.chainid == 1) {
            l1Fed = new OptiFed(l1gov, address(0x69), 1_000_000e18);

            vm.stopPrank();
            vm.startPrank(l1gov);
            L1DOLA.addMinter(address(l1Fed));
        } else {
            l2fed = new VeloFarmer(payable(address(router)), address(rewards), address(L2DOLA), address(USDC), gov, l2optiBridgeAddress, optiFedAddress);

            vm.stopPrank();
            vm.startPrank(gov);
            l2fed.setMaxSlippage(200);
        }

        vm.stopPrank();
    }

    // L1

    function testL1_OptiFedExpansion() public {
        vm.startPrank(chair);

        uint prevBal = L1DOLA.balanceOf(l1optiBridgeAddress);

        l1Fed.expansion(dolaAmount);

        assertEq(prevBal + dolaAmount, L1DOLA.balanceOf(l1optiBridgeAddress));
    }

    function testL1_OptiFedExpansionAndSwap() public {
        vm.startPrank(chair);

        uint prevBal = L1DOLA.balanceOf(l1optiBridgeAddress);

        l1Fed.expansionAndSwap(dolaAmount);

        assertEq(prevBal + dolaAmount / 2, L1DOLA.balanceOf(l1optiBridgeAddress));
    }

    function testL1_changeVeloFarmer_fail_whenCalledByNonGov() public {
        vm.startPrank(chair);

        vm.expectRevert(OnlyGov.selector);
        l1Fed.changeVeloFarmer(user);
    }

    function testL1_changeChair_fail_whenCalledByNonGov() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyGov.selector);
        l1Fed.changeChair(user);
    }

    function testL1_changeGov_fail_whenCalledByNonGov() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyGov.selector);
        l1Fed.changeGov(user);
    }

    function testL1_setMaxDailyDelta_fail_whenCalledByNonGov() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyGov.selector);
        l1Fed.setMaxDailyDelta(1e18);
    }
    
    function testL1_setMaxSlippage_fail_whenCalledByNonGov() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyGov.selector);
        l1Fed.setMaxSlippage(500);
    }

    function testL1_resign_fail_whenCalledByNonChair() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyChair.selector);
        l1Fed.resign();
    }

    function testL1_swapDOLAtoUSDC_fail_whenCalledByNonChair() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyChair.selector);
        l1Fed.swapDOLAtoUSDC(1e18);
    }

    function testL1_swapUSDCtoDOLA_fail_whenCalledByNonChair() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyChair.selector);
        l1Fed.swapUSDCtoDOLA(1e6);
    }

    function testL1_contractAll_fail_whenCalledByNonChair() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyChair.selector);
        l1Fed.contractAll();
    }

    function testL1_contract_fail_whenCalledByNonChair() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyChair.selector);
        l1Fed.contraction(1e18);
    }

    // L2

    function testL2_SwapAndClaimVeloRewards() public {
        gibDOLA(address(l2fed), dolaAmount * 3);

        vm.startPrank(chair);
        l2fed.swapAndDeposit(dolaAmount);
        vm.roll(block.number + 10000);
        vm.warp(block.timestamp + (10_000 * 60));
        l2fed.claimVeloRewards();
        VELO.balanceOf(address(l2fed));
    }

    function testL2_SwapAndClaimRewards() public {
        gibDOLA(address(l2fed), dolaAmount * 3);

        vm.startPrank(chair);
        l2fed.swapAndDeposit(dolaAmount);
        vm.roll(block.number + 10000);
        vm.warp(block.timestamp + (10_000 * 60));
        address[] memory addr = new address[](1);
        addr[0] = 0x3c8B650257cFb5f272f799F5e2b4e65093a11a05;
        l2fed.claimRewards(addr);
        VELO.balanceOf(address(l2fed));
    }

    function testL2_Deposit() public {
        gibDOLA(address(l2fed), dolaAmount * 3);
        gibUSDC(address(l2fed), usdcAmount * 3);

        vm.startPrank(chair);
        l2fed.depositAll();
    }

    function testL2_Swap() public {
        gibDOLA(address(l2fed), dolaAmount * 3);

        vm.startPrank(chair);
        l2fed.swapAndDeposit(dolaAmount);
    }

    function testL2_WithdrawFiftyPercent() public {
        gibDOLA(address(l2fed), dolaAmount * 3);

        vm.startPrank(chair);
        l2fed.swapAndDeposit(dolaAmount);
        l2fed.withdrawLiquidity(50);

        emit log_named_uint("DOLA bal", L2DOLA.balanceOf(address(l2fed)));
        emit log_named_uint("USDC bal", USDC.balanceOf(address(l2fed)));
        emit log_named_uint("LP bal", IERC20(address(dolaGauge)).balanceOf(address(l2fed)));
    }

    function testL2_WithdrawAll() public {
        gibDOLA(address(l2fed), dolaAmount * 3);

        vm.startPrank(chair);
        l2fed.swapAndDeposit(dolaAmount);
        l2fed.withdrawLiquidity(100);

        emit log_named_uint("DOLA bal", L2DOLA.balanceOf(address(l2fed)));
        emit log_named_uint("USDC bal", USDC.balanceOf(address(l2fed)));
        emit log_named_uint("LP bal", IERC20(address(dolaGauge)).balanceOf(address(l2fed)));

        l2fed.withdrawToL1OptiFed(L2DOLA.balanceOf(address(l2fed)));
        emit log_named_uint("DOLA bal", L2DOLA.balanceOf(address(l2fed)));
    }

    function testL2_WithdrawAndSwapAll() public {
        gibDOLA(address(l2fed), dolaAmount * 3);

        vm.startPrank(chair);
        l2fed.swapAndDeposit(dolaAmount);
        l2fed.withdrawLiquidityAndSwapToDOLA(100);

        emit log_named_uint("DOLA bal", L2DOLA.balanceOf(address(l2fed)));
        emit log_named_uint("USDC bal", USDC.balanceOf(address(l2fed)));
        emit log_named_uint("LP bal", IERC20(address(dolaGauge)).balanceOf(address(l2fed)));

        l2fed.withdrawToL1OptiFed(L2DOLA.balanceOf(address(l2fed)));
        emit log_named_uint("DOLA bal", L2DOLA.balanceOf(address(l2fed)));
    }

    function testL2_resign_fail_whenCalledByNonChair() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyChair.selector);
        l2fed.resign();
    }

    function testL2_setMaxSlippage_fail_whenCalledByNonGov() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyGov.selector);
        l2fed.setMaxSlippage(500);
    }

    function testL2_changeGov_fail_whenCalledByNonGov() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyGov.selector);
        l2fed.changeGov(user);
    }
    
    function testL2_changeChair_fail_whenCalledByNonGov() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyGov.selector);
        l2fed.changeChair(user);
    }

    function testL2_changeOptiFed_fail_whenCalledByNonGov() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyGov.selector);
        l2fed.changeOptiFed(user);
    }

    //Helper Functions

    function gibAnTokens(address _user, address _anToken, uint _amount) internal {
        bytes32 slot;
        assembly {
            mstore(0, _user)
            mstore(0x20, 0xE)
            slot := keccak256(0, 0x40)
        }

        vm.store(_anToken, slot, bytes32(_amount));
    }

    function gibDOLA(address _user, uint _amount) internal {
        bytes32 slot;
        assembly {
            mstore(0, _user)
            mstore(0x20, 0x0)
            slot := keccak256(0, 0x40)
        }

        vm.store(address(L2DOLA), slot, bytes32(_amount));
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
