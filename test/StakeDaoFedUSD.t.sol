pragma solidity ^0.8.13;

import "ds-test/test.sol";
import "forge-std/Vm.sol";
import "src/stakedao-fed/StakeDaoFed.sol";
import "src/stakedao-fed/BalancerAdapter.sol";
import "src/interfaces/IERC20.sol";
import "src/interfaces/stakedao/IBalancerVault.sol";
import "src/interfaces/stakedao/IGauge.sol";
import "src/interfaces/stakedao/IClaimRewards.sol";

interface IMintable is IERC20 {
    function addMinter(address) external;
}

contract Swapper is BalancerComposableStablepoolAdapter {
    constructor(bytes32 poolId_, address dola_, address vault_, address bpt_) BalancerComposableStablepoolAdapter(poolId_, dola_, vault_, bpt_){}

    function swapExact(address assetIn, address assetOut, uint amount) public{
        swapExactIn(assetIn, assetOut, amount, 1);
    }
}

contract StakeDaoFedTest is DSTest{
    Vm internal constant vm = Vm(HEVM_ADDRESS);
    IMintable dola = IMintable(0x7945b0A6674b175695e5d1D08aE1e6F13744Abb0);
    IERC20 bpt = IERC20(0x7E9AfD25F5Ec0eb24d7d4b089Ae7EcB9651c8b1F);
    IERC20 bal = IERC20(0xba100000625a3754423978a60c9317c58a424e3D);
    IERC20 std = IERC20(0x73968b9a57c6E53d41345FD57a6E6ae27d6CDB2F);
    address vault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address baoGauge = 0x1A44E35d5451E0b78621A1B3e7a53DFaA306B1D0;
    address sdbaousdGauge = 0xC6A0B204E28C05838b8B1C36f61963F16eCD64C4;
    address balancerVault = 0xd9663A5e08f0B3db295C5346C1B52677B7398585;
    address rewards = 0xA57b8d98dAE62B26Ec3bcC4a365338157060B234;
    address chair = address(0xA);
    address guardian = address(0xB);
    address minter = address(0xB);
    address gov = address(0xFC69e0a5823E2AfCBEb8a35d33588360F1496a00);
    uint maxLossExpansion = 500;
    uint maxLossWithdraw = 500;
    uint maxLossTakeProfit = 500;
    bytes32 poolId = bytes32(0x7e9afd25f5ec0eb24d7d4b089ae7ecb9651c8b1f000000000000000000000511);
    address holder = 0xFC69e0a5823E2AfCBEb8a35d33588360F1496a00;
    StakeDaoFed fed;
    Swapper swapper;

    function setUp() public {

        StakeDaoFed.InitialAddresses memory addresses = StakeDaoFed.InitialAddresses(
            address(dola),
            address(bal), 
            address(std), 
            vault, 
            address(bpt),
            balancerVault,
            baoGauge,
            sdbaousdGauge,
            rewards,
            chair,
            guardian,
            gov
        );

        fed = new StakeDaoFed(
            addresses,
            maxLossExpansion,
            maxLossWithdraw,
            maxLossTakeProfit,
            poolId
        );
        swapper = new Swapper(poolId, address(dola), vault, address(bpt));
        vm.startPrank(gov);
        dola.addMinter(address(fed));
        dola.addMinter(minter);
        vm.stopPrank();
    }

    function testExpansion_succeed_whenExpandedWithinAcceptableSlippage() public {
        uint amount = 1000 ether;     
        uint initialDolaSupply = fed.dolaSupply();
        uint initialbptSupply = fed.bptSupply();
        uint initialDolaTotalSupply = dola.totalSupply();

        vm.prank(chair);
        fed.expansion(amount);

        assertEq(initialDolaTotalSupply + amount, dola.totalSupply());
        assertEq(initialDolaSupply + amount, fed.dolaSupply());
        //TODO: Should have greater precision about the amount of balLP acquired
        assertGt(fed.bptSupply(), initialbptSupply);
    }

    function testFailExpansion_fail_whenExpandedOutsideAcceptableSlippage() public {
        uint amount = 1000_000_000 ether;

        vm.prank(chair);
        fed.expansion(amount);
    }

    function testburnRemainingDolaSupply_Success() public {
        vm.startPrank(chair);
        fed.expansion(1000 ether);
        vm.stopPrank();       
        vm.startPrank(minter);
        dola.mint(address(minter), 1000 ether);
        dola.approve(address(fed), 1000 ether);

        fed.burnRemainingDolaSupply();
        assertEq(fed.dolaSupply(), 0);
    }

    function testContraction_succeed_whenContractedWithinAcceptableSlippage() public {
        uint amount = 1 ether;
        vm.prank(chair);
        fed.expansion(amount*2);
        uint initialDolaSupply = fed.dolaSupply();
        uint initialDolaTotalSupply = dola.totalSupply();
        uint initialBalLpSupply = fed.bptSupply();

        vm.prank(chair);
        fed.contraction(amount);

        //Make sure basic accounting of contraction is correct:
        assertGt(initialBalLpSupply, fed.bptSupply());
        assertGt(initialDolaSupply, fed.dolaSupply());
        assertGt(initialDolaTotalSupply, dola.totalSupply());
        assertEq(initialDolaTotalSupply - dola.totalSupply(), initialDolaSupply - fed.dolaSupply());

        //Make sure maxLoss wasn't exceeded
        assertLe(initialDolaSupply-fed.dolaSupply(), amount*10_000/(10_000-maxLossWithdraw), "Amount withdrawn exceeds maxloss"); 
        assertLe(initialDolaTotalSupply-dola.totalSupply(), amount*10_000/(10_000-maxLossWithdraw), "Amount withdrawn exceeds maxloss");
    }

    function testContraction_FailWithOnlyChair_whenCalledByOtherAddress() public {
        vm.prank(gov);
        vm.expectRevert("ONLY CHAIR");
        fed.contraction(1000);
    }

    function testSetMaxLossExpansionBps_succeed_whenCalledByGov() public {
        uint initial = fed.maxLossExpansionBps();
        
        vm.prank(gov);
        fed.setMaxLossExpansionBps(1);

        assertEq(fed.maxLossExpansionBps(), 1);
        assertTrue(initial != fed.maxLossExpansionBps());
    }

    function testSetMaxLossWithdrawBps_succeed_whenCalledByGov() public {
        uint initial = fed.maxLossWithdrawBps();
        
        vm.prank(gov);
        fed.setMaxLossWithdrawBps(1);

        assertEq(fed.maxLossWithdrawBps(), 1);
        assertTrue(initial != fed.maxLossWithdrawBps());
    }

    function testSetMaxLossTakeProfitBps_succeed_whenCalledByGov() public {
        uint initial = fed.maxLossTakeProfitBps();
        
        vm.prank(gov);
        fed.setMaxLossTakeProfitBps(1);

        assertEq(fed.maxLossTakeProfitBps(), 1);
        assertTrue(initial != fed.maxLossTakeProfitBps());
    }

    function testSetMaxLossExpansionBps_fail_whenCalledByNonGov() public {
        uint initial = fed.maxLossExpansionBps();
        
        vm.expectRevert("ONLY GOV");
        fed.setMaxLossExpansionBps(1);

        assertEq(fed.maxLossExpansionBps(), initial);
    }

    function testSetMaxLossWithdrawBps_fail_whenCalledByGov() public {
        uint initial = fed.maxLossWithdrawBps();
        
        vm.expectRevert("ONLY GOV OR GUARDIAN");
        fed.setMaxLossWithdrawBps(1);

        assertEq(fed.maxLossWithdrawBps(), initial);
    }

    function testSetMaxLossTakeProfitBps_fail_whenCalledByGov() public {
        uint initial = fed.maxLossTakeProfitBps();
        
        vm.expectRevert("ONLY GOV");
        fed.setMaxLossTakeProfitBps(1);

        assertEq(fed.maxLossTakeProfitBps(), initial);
    }

    function washTrade(uint loops, uint amount) public {
        vm.stopPrank();     
        vm.startPrank(minter);
        dola.mint(address(swapper), amount);
        //Trade back and forth to create a profit
        for(uint i; i < loops; i++){
            swapper.swapExact(address(dola), address(bpt), dola.balanceOf(address(swapper)));
            swapper.swapExact(address(bpt), address(dola), bpt.balanceOf(address(swapper)));
        }
        vm.stopPrank();     
    }
}
