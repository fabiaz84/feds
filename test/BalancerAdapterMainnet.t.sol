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

    function bptUSDValue(uint amount, bool optimistic) public returns(uint){
        return _bptUSDValue(amount, optimistic);
    }
}

contract BalancerAdapterTest is DSTest{
    Vm internal constant vm = Vm(HEVM_ADDRESS);
    address vault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address dola = 0x865377367054516e17014CcdED1e7d814EDC9ce4;
    bytes32 poolId = bytes32(0xa13a9247ea42d743238089903570127dda72fe4400000000000000000000035d);
    address holder = 0x4D2F01D281Dd0b98e75Ca3E1FdD36823B16a7dbf;
    PublicBalancerAdapter adapter;

    function setUp() public {
        adapter = new PublicBalancerAdapter(poolId, dola, vault);
        vm.prank(holder);
        IERC20(dola).transfer(address(adapter), 1 ether);
    }

    function testDeposit_success_whenDepositingZero() public {
        adapter.deposit(1 ether, 0);
    }

    function testbptUsdValue() public {
        emit log_uint(adapter.bptUSDValue(1 ether, true));
        emit log_uint(adapter.bptUSDValue(1 ether, false));
    }
    


}
