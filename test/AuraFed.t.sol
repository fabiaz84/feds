pragma solidity ^0.8.13;

import "ds-test/test.sol";
import "forge-std/Vm.sol";
import "src/aura-fed/AuraFed.sol";
import "src/interfaces/IERC20.sol";

interface IMintable is IERC20 {
    function addMinter(address) external;
}

contract AuraFedTest is DSTest{
    Vm internal constant vm = Vm(HEVM_ADDRESS);
    IMintable dola = IMintable(0x865377367054516e17014CcdED1e7d814EDC9ce4);
    address auraBal = 0x616e8BfA43F920657B3497DBf40D6b1A02D4608d;
    address aura = 0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF;
    address vault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address baseRewardPool = 0x5e5ea2048475854a5702F5B8468A51Ba1296EFcC;
    address auraLocker = 0x3Fa73f1E5d8A792C80F426fc8F84FBF7Ce9bBCAC;
    address chair = address(0xA);
    address gov = address(0x926dF14a23BE491164dCF93f4c468A50ef659D5B);
    uint maxLossExpansion = 20;
    uint maxLossWithdraw = 20;
    uint maxLossTakeProfit = 20;
    bytes32 poolId = bytes32(0x5b3240b6be3e7487d61cd1afdfc7fe4fa1d81e6400000000000000000000037b);
    address holder = 0x4D2F01D281Dd0b98e75Ca3E1FdD36823B16a7dbf;
    AuraFed fed;

    function setUp() public {
        fed = new AuraFed(
            address(dola), 
            auraBal, 
            aura, 
            vault, 
            baseRewardPool,
            auraLocker,
            chair, 
            gov,
            maxLossExpansion,
            maxLossWithdraw,
            maxLossTakeProfit,
            poolId
        );
        vm.startPrank(gov);
        dola.addMinter(address(fed));
        vm.stopPrank();
    }

    function testExpansion_succeed_whenExpandedWithinAcceptableSlippage() public {
        uint amount = 1 ether;     
        uint initialDolaSupply = fed.dolaSupply();
        uint initialbptSupply = fed.bptSupply();
        uint initialDolaTotalSupply = dola.totalSupply();

        vm.prank(chair);
        fed.expansion(amount);

        assertEq(initialDolaTotalSupply + amount, dola.totalSupply());
        assertEq(initialDolaSupply + amount, fed.dolaSupply());
        //TODO: Should have greater precision about the amount of crvLP acquired
        assertGt(fed.bptSupply(), initialbptSupply);
    }


}
