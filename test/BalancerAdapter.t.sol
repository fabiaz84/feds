pragma solidity ^0.8.13;

import "ds-test/test.sol";
import "forge-std/Vm.sol";
import "src/aura-fed/BalancerAdapter.sol";
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
    IMintable dola = IMintable(0xf4edfad26EE0D23B69CA93112eccE52704E0006f);
    address bbausd = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    IERC20 bpt = IERC20(0x1a44e35d5451e0b78621a1b3e7a53dfaa306b1d0);
    address vault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address minter = address(0xB);
    address gov = address(0xFC69e0a5823E2AfCBEb8a35d33588360F1496a00);
    bytes32 poolId = bytes32(0x1a44e35d5451e0b78621a1b3e7a53dfaa306b1d000000000000000000000051b);
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

    function testManipulate_getRate_when_TradingTokens() public {
       uint bptNeededBefore = swapper.bptNeededForDola(1 ether); 
       vm.prank(minter);
       dola.mint(address(swapper), 1000_000 ether);
       swapper.swapExact(address(dola), address(bbausd), 10_000 ether);
       uint bptNeededAfter = swapper.bptNeededForDola(1 ether);
       assertGt(bptNeededBefore * 10000 / 9990, bptNeededAfter);
       assertLt(bptNeededBefore * 9990 / 10000, bptNeededAfter);
       swapper.swapExact(address(bbausd), address(dola), IERC20(bbausd).balanceOf(address(swapper)));
       uint bptNeededAfterAfter = swapper.bptNeededForDola(1 ether);
       assertGt(bptNeededBefore * 10000 / 9990, bptNeededAfterAfter);
       assertLt(bptNeededBefore * 9990 / 10000, bptNeededAfterAfter);
       emit log_uint(bptNeededBefore);
       emit log_uint(bptNeededAfter);
       emit log_uint(bptNeededAfterAfter);   
    }
}

