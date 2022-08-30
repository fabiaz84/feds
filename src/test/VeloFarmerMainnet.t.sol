// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "ds-test/test.sol";
import "forge-std/Test.sol";
import { IERC20 } from "../interfaces/IERC20.sol";
import { IDola } from "../interfaces/velo/IDola.sol";
import "../velo-fed/VeloFarmer.sol";
import {OptiFed} from "../velo-fed/OptiFed.sol";

contract VeloFarmerMainnetTest is Test {
    //Tokens
    IRouter public router = IRouter(payable(0xa132DAB612dB5cB9fC9Ac426A0Cc215A3423F9c9));
    IGauge public dolaGauge = IGauge(0xAFD2c84b9d1cd50E7E18a55e419749A6c9055E1F);
    IDola public DOLA = IDola(0x8aE125E8653821E851F12A49F7765db9a9ce7384);
    IERC20 public VELO = IERC20(0x3c8B650257cFb5f272f799F5e2b4e65093a11a05);
    IERC20 public USDC = IERC20(0x7F5c764cBc14f9669B88837ca1490cCa17c31607);
    address public l2optiBridgeAddress = 0x4200000000000000000000000000000000000010;
    address public dolaUsdcPoolAddy = 0x6C5019D345Ec05004A7E7B0623A91a0D9B8D590d;
    address public optiFedAddress = address(0xA);

    //EOAs
    address user = address(69);
    address chair = address(0xB);
    address gov = address(0x607);

    //Numbas
    uint dolaAmount = 100_000e18;
    uint usdcAmount = 100_000e6;

    //Feds
    VeloFarmer fed;

    error OnlyGov();
    error OnlyChair();
    error PercentOutOfRange();
    
    function setUp() public {
        vm.startPrank(chair);

        fed = new VeloFarmer(payable(address(router)), address(DOLA), address(USDC), gov, l2optiBridgeAddress, optiFedAddress);

        vm.stopPrank();
        vm.startPrank(gov);
        fed.setMaxSlippageDolaToUsdc(500);
        fed.setMaxSlippageUsdcToDola(100);
        fed.setMaxSlippageLiquidity(4500);

        vm.stopPrank();
    }

    // L2

    function testL2_SwapAndClaimVeloRewards() public {
        gibDOLA(address(fed), dolaAmount * 3);

        uint initialVelo = VELO.balanceOf(address(fed));

        vm.startPrank(chair);
        fed.swapAndDeposit(dolaAmount);
        vm.roll(block.number + 10000);
        vm.warp(block.timestamp + (10_000 * 60));
        fed.claimVeloRewards();

        assertGt(VELO.balanceOf(address(fed)), initialVelo, "No rewards claimed");
    }

    function testL2_DepositAndClaimVeloRewards() public {
        gibDOLA(address(fed), dolaAmount * 3);
        gibUSDC(address(fed), usdcAmount * 3);

        uint initialVelo = VELO.balanceOf(address(fed));

        vm.startPrank(chair);
        fed.deposit(dolaAmount / 2, usdcAmount / 2);

        vm.roll(block.number + 10000);
        vm.warp(block.timestamp + (10_000 * 60));
        fed.claimVeloRewards();

        assertGt(VELO.balanceOf(address(fed)), initialVelo, "No rewards claimed");
    }

    function testL2_SwapAndClaimRewards() public {
        gibDOLA(address(fed), dolaAmount * 3);

        uint initialVelo = VELO.balanceOf(address(fed));

        vm.startPrank(chair);
        fed.swapAndDeposit(dolaAmount);
        vm.roll(block.number + 10000);
        vm.warp(block.timestamp + (10_000 * 60));
        address[] memory addr = new address[](1);
        addr[0] = 0x3c8B650257cFb5f272f799F5e2b4e65093a11a05;
        fed.claimRewards(addr);

        assertGt(VELO.balanceOf(address(fed)), initialVelo, "No rewards claimed");
    }

    function testL2_Deposit(uint amountDola, uint amountUsdc) public {
        amountDola = bound(amountDola, 10e18, 1_000_000_000e18);
        amountUsdc = bound(amountUsdc, 10e6, 1_000_000_000e6);
        gibDOLA(address(fed), amountDola);
        gibUSDC(address(fed), amountUsdc);

        vm.startPrank(chair);

        fed.depositAll();
    }

    function testL2_SwapAndDeposit_Fails_WhenSlippageGtMaxDolaToUsdcSlippage() public {
        gibDOLA(address(fed), dolaAmount * 3);

        vm.startPrank(gov);
        fed.setMaxSlippageDolaToUsdc(100);
        vm.stopPrank();

        vm.startPrank(chair);
        vm.expectRevert("Router: INSUFFICIENT_OUTPUT_AMOUNT");
        fed.swapAndDeposit(dolaAmount);
    }

    function testL2_SwapDolaToUsdc_Fails_WhenSlippageGtMaxDolaToUsdcSlippage() public {
        gibDOLA(address(fed), dolaAmount * 3);

        vm.startPrank(gov);
        fed.setMaxSlippageDolaToUsdc(100);
        vm.stopPrank();

        vm.startPrank(chair);
        vm.expectRevert("Router: INSUFFICIENT_OUTPUT_AMOUNT");
        fed.swapDOLAtoUSDC(dolaAmount);
    }

    function testL2_SwapUsdcToDola_Fails_WhenSlippageGtMaxUsdcToDolaSlippage() public {
        gibUSDC(address(fed), usdcAmount * 3);

        uint usdcToSwap = usdcAmount * 3;
        gibUSDC(address(user), usdcToSwap);
        vm.startPrank(user);
        USDC.approve(address(router), type(uint).max);
        router.swapExactTokensForTokensSimple(usdcToSwap, 0, address(USDC), address(DOLA), true, address(user), block.timestamp);
        vm.stopPrank();

        vm.startPrank(gov);
        fed.setMaxSlippageUsdcToDola(100);
        vm.stopPrank();

        vm.startPrank(chair);
        vm.expectRevert("Router: INSUFFICIENT_OUTPUT_AMOUNT");
        fed.swapUSDCtoDOLA(usdcAmount);
    }

    function testL2_Withdraw(uint amountDola) public {
        amountDola = bound(amountDola, 10_000e18, 1_000_000_000e18);    

        vm.startPrank(l2optiBridgeAddress);
        DOLA.mint(address(fed), amountDola);
        USDC.mint(address(fed), amountDola / 1e12);
        vm.stopPrank();

        vm.startPrank(gov);
        fed.setMaxSlippageLiquidity(4000);
        vm.stopPrank();

        vm.startPrank(chair);
        fed.depositAll();
        fed.withdrawLiquidity(amountDola);
        
        fed.withdrawToL1OptiFed(DOLA.balanceOf(address(fed)), USDC.balanceOf(address(fed)));
    }

    function testL2_WithdrawAndSwap(uint amountDola) public {
        amountDola = bound(amountDola, 10_000e18, 1_000_000e18);    

        vm.startPrank(l2optiBridgeAddress);
        DOLA.mint(address(fed), amountDola / 2);
        USDC.mint(address(fed), amountDola / 2 / 1e12);
        vm.stopPrank();

        vm.startPrank(gov);
        fed.setMaxSlippageLiquidity(4000);
        fed.setMaxSlippageUsdcToDola(5000);
        vm.stopPrank();

        vm.startPrank(chair);
        fed.depositAll();

        fed.withdrawLiquidityAndSwapToDOLA(amountDola);
    }

    function testL2_resign_fail_whenCalledByNonChair() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyChair.selector);
        fed.resign();
    }

    function testL2_setMaxSlippageDolaToUsdc_fail_whenCalledByNonGov() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyGov.selector);
        fed.setMaxSlippageDolaToUsdc(500);
    }

    function testL2_setMaxSlippageUsdcToDola_fail_whenCalledByNonGov() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyGov.selector);
        fed.setMaxSlippageUsdcToDola(500);
    }

    function testL2_changeGov_fail_whenCalledByNonGov() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyGov.selector);
        fed.changeGov(user);
    }
    
    function testL2_changeChair_fail_whenCalledByNonGov() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyGov.selector);
        fed.changeChair(user);
    }

    function testL2_changeOptiFed_fail_whenCalledByNonGov() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyGov.selector);
        fed.changeOptiFed(user);
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
