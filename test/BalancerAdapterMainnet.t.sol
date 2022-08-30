pragma solidity ^0.8.13;

import "ds-test/test.sol";
import "forge-std/Vm.sol";
import "src/aura-fed/BalancerAdapter.sol";

contract PublicBalancerAdapter is BalancerMetapoolAdapter{
    constructor(bytes32 poolId_, address token_, address vault_) BalancerMetapoolAdapter(poolId_, token_, vault_){}

    function deposit(uint dolaAmount, uint maxLossBps) public {
        _deposit(dolaAmount, maxLossBps);
    }

    function withdraw(uint dolaAmount, uint maxLossBps) public {
        _withdraw(dolaAmount, maxLossBps);
    }
}

contract BalancerAdapterTest is DSTest{
    Vm internal constant vm = Vm(HEVM_ADDRESS);
    address vault = address(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    address token = address(0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF);
    bytes32 poolId = bytes32(0xcfca23ca9ca720b6e98e3eb9b6aa0ffc4a5c08b9000200000000000000000274);
    address holder = 0x054BA12713290eF5B9236E55944713c0Edeb4Cf4;
    PublicBalancerAdapter adapter;

    function setUp() public {
        adapter = new PublicBalancerAdapter(poolId, token, vault);
        vm.prank(holder);
        IERC20(token).transfer(address(adapter), 1 ether);
    }

    function testDeposit_success_whenDepositingZero() public {
        adapter.deposit(1 ether, 0);
    }
}
