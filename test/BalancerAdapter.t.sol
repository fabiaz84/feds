pragma solidity ^0.8.13;

import "ds-test/test.sol";
import "forge-std/Vm.sol";
import "src/stakedao-fed/BalancerAdapter.sol";
import "src/interfaces/IERC20.sol";

interface IMintable is IERC20 {
    function addMinter(address) external;
}

contract Swapper is BalancerComposableStablepoolAdapter {
    constructor(bytes32 poolId_, address dola_, address vault_, address bpt_) BalancerComposableStablepoolAdapter(poolId_, dola_, vault_, bpt_){}

    function swapExact(address assetIn, address assetOut, uint amount) public{
        swapExactIn(assetIn, assetOut, amount, 1);
    }
}

contract BalancerTest is DSTest{
    Vm internal constant vm = Vm(HEVM_ADDRESS);
    IMintable dola = IMintable(0x7945b0A6674b175695e5d1D08aE1e6F13744Abb0);
    address bbausd = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;
    IERC20 bpt = IERC20(0x7E9AfD25F5Ec0eb24d7d4b089Ae7EcB9651c8b1F);
    address vault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address minter = address(0xB);
    address gov = address(0xFC69e0a5823E2AfCBEb8a35d33588360F1496a00);
    bytes32 poolId = bytes32(0x7e9afd25f5ec0eb24d7d4b089ae7ecb9651c8b1f000000000000000000000511);
    address holder = 0xFC69e0a5823E2AfCBEb8a35d33588360F1496a00;
    Swapper swapper;

    function setUp() public {
        swapper = new Swapper(poolId, address(dola), vault,address(bpt));
        vm.prank(gov);
        dola.addMinter(minter);
    }

    function testManipulate_getRate_when_AddingAndRemovingLP() public {
       uint bptNeededBefore = swapper.bptNeededForDola(1 ether); 
       vm.prank(minter);
       dola.mint(address(swapper), 1000_000_000 ether);
       swapper.swapExact(address(dola), address(bpt), 1000_000_000 ether);
       uint bptNeededAfter = swapper.bptNeededForDola(1 ether);
       assertGt(bptNeededBefore * 10000 / 9990, bptNeededAfter);
       assertLt(bptNeededBefore * 9990 / 10000, bptNeededAfter);
       swapper.swapExact(address(bpt), address(dola), bpt.balanceOf(address(swapper)));
       uint bptNeededAfterAfter = swapper.bptNeededForDola(1 ether);
       assertGt(bptNeededBefore * 10000 / 9990, bptNeededAfterAfter);
       assertLt(bptNeededBefore * 9990 / 10000, bptNeededAfterAfter);
       emit log_uint(bptNeededBefore);
       emit log_uint(bptNeededAfter);
       emit log_uint(bptNeededAfterAfter);
    }
}

