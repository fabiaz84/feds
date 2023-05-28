// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "ds-test/test.sol";
import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IDola} from "src/interfaces/velo/IDola.sol";
import {ArbiGovMessengerL1} from "src/arbi-fed/ArbiGovMessengerL1.sol";
import {AuraFarmer} from "src/arbi-fed/AuraFarmer.sol";
import "src/interfaces/aura/IAuraBalRewardPool.sol";
import "src/interfaces/balancer/IComposablePoolFactory.sol";
import "src/interfaces/balancer/IVault.sol";
import {GovernorL2} from "src/l2-gov/GovernorL2.sol";
import {AddressAliasHelper} from "src/utils/AddressAliasHelper.sol";
import {IL2GatewayRouter} from "src/interfaces/arbitrum/IL2GatewayRouter.sol";

contract MockAuraRewardPool  {
    address internal token;

    constructor(address rewardToken_) {
        token = rewardToken_;
    }   

    function rewardToken() external view returns (address) {
        return token;
    }
}

contract MockVault {
    address internal bpt;

    constructor(address mockBpt) {
        bpt = mockBpt;
    }
    function getPool(bytes32 poolId) external view returns (address, address) {
        return (bpt, address(0x0));
    }
}

contract AuraFarmerTest is Test {
    
    error ExpansionMaxLossTooHigh();
    error WithdrawMaxLossTooHigh();
    error TakeProfitMaxLossTooHigh();
    error OnlyL2Chair();
    error OnlyL2Gov();
    error MaxSlippageTooHigh();
    error NotEnoughTokens();
    error NotEnoughBPT();
    error AuraWithdrawFailed();
    error NothingWithdrawn();
    error OnlyChairCanTakeBPTProfit();
    error NoProfit();
    error GettingRewardFailed();

    //L1
    IDola public DOLA = IDola(0x865377367054516e17014CcdED1e7d814EDC9ce4);
    IERC20 public USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 bpt = IERC20(0xFf4ce5AAAb5a627bf82f4A571AB1cE94Aa365eA6); // USDC-DOLA bal pool
    IERC20 bal = IERC20(0xba100000625a3754423978a60c9317c58a424e3D);
    IERC20 aura = IERC20(0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF);
    IVault vault = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    IAuraBalRewardPool baseRewardPool =
        IAuraBalRewardPool(0x99653d46D52eE41c7b35cbAd1aC408A00bad6A76);
    address booster = 0xA57b8d98dAE62B26Ec3bcC4a365338157060B234;
    address gov = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;
    ArbiGovMessengerL1 arbiGovMessengerL1;

    // Arbitrum
    IDola public DOLAArbi = IDola(0x6A7661795C374c0bFC635934efAddFf3A7Ee23b6);
    IERC20 public USDCArbi = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    address dolaUser = 0x052f7890E50fb5b921BCAb3B10B79a58A3B9d40f; 
    address usdcUser = 0x5bdf85216ec1e38D6458C870992A69e38e03F7Ef;
    GovernorL2 governor;
    address l2MessengerAlias;
    address l2Chair = address(0x69);
    address arbiFedL1 = address(0x23);
    IAuraBalRewardPool mockBaseRewardPoolArbi;
    IVault mockVault;
    // Actual addresses
    IL2GatewayRouter public immutable l2Gateway = IL2GatewayRouter(0x5288c571Fd7aD117beA99bF60FE0846C4E84F933); 
    address l2GatewayOutbound = 0x09e9222E96E7B4AE2a407B98d48e330053351EEe;

    // Dummy values
    bytes32 poolId =
        bytes32(
            0xff4ce5aaab5a627bf82f4a571ab1ce94aa365ea6000200000000000000000426
        );

    // Values taken from AuraFed for USDC-DOLA 0x1CD24E3FBae88BECbaFED4b8Cda765D1e6e3BC03
    uint maxLossExpansion = 13;
    uint maxLossWithdraw = 10;
    uint maxLossTakeProfit = 10;

    //Numbas
    uint dolaAmount = 1000e18;
    uint usdcAmount = 1000e6;
    //Feds
    AuraFarmer auraFarmer;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("arbitrum"), 93907980);

        arbiGovMessengerL1 = new ArbiGovMessengerL1(gov);
        
        l2MessengerAlias = AddressAliasHelper.applyL1ToL2Alias(address(arbiGovMessengerL1));

        governor = new GovernorL2(address(arbiGovMessengerL1));

        mockBaseRewardPoolArbi = IAuraBalRewardPool(address(new MockAuraRewardPool(address(USDCArbi)))); // Dummy value 

        mockVault = IVault(address(new MockVault(address(USDCArbi))));
        
        AuraFarmer.InitialAddresses memory addresses = AuraFarmer.InitialAddresses(
            address(DOLAArbi),
            address(mockVault), // mock
            address(mockBaseRewardPoolArbi), // mock
            address(DOLAArbi), //bpt
            booster,
            l2Chair,
            address(governor),
            arbiFedL1,
            address(arbiGovMessengerL1)
        );


        // Deploy Aura Farmer
        auraFarmer = new AuraFarmer(
            addresses,
            maxLossExpansion,
            maxLossWithdraw,
            maxLossTakeProfit,
            poolId
        );

        vm.stopPrank();
    }

    function test_initialized_properly() public {
        
        assertEq(auraFarmer.l2Chair(), l2Chair);
        assertEq(auraFarmer.l2Gov(), address(governor));
        assertEq(governor.govMessenger(), address(arbiGovMessengerL1));
    }

    function test_changeGov() public {
        
        vm.expectRevert(OnlyL2Gov.selector);
        auraFarmer.changeGov(address(0));

        bytes memory data = abi.encodeWithSelector(AuraFarmer.changeGov.selector, address(0));

        vm.prank(l2MessengerAlias); // simulating a message from the aliased L1 Arbi Messenger to call the governor
        governor.execute(address(auraFarmer), data);

        assertEq(auraFarmer.l2Gov(), address(0));
    }

    function test_changeL2Chair() public {
        vm.expectRevert(OnlyL2Gov.selector);
        auraFarmer.changeGov(address(0x70));

        bytes memory data = abi.encodeWithSelector(AuraFarmer.changeL2Chair.selector, address(0x70));

        vm.prank(l2MessengerAlias);
        governor.execute(address(auraFarmer), data);

        assertEq(auraFarmer.l2Chair(), address(0x70));
    }


    function test_setMaxLossExpansionBPS() public {
        vm.expectRevert(OnlyL2Gov.selector);
        auraFarmer.setMaxLossExpansionBps(0);

        bytes memory data = abi.encodeWithSelector(AuraFarmer.setMaxLossExpansionBps.selector, 0);

        vm.prank(l2MessengerAlias);
        governor.execute(address(auraFarmer), data);

        assertEq(auraFarmer.maxLossExpansionBps(), 0);

        data = abi.encodeWithSelector(AuraFarmer.setMaxLossExpansionBps.selector, 10000);

        vm.expectRevert(ExpansionMaxLossTooHigh.selector);
        vm.prank(l2MessengerAlias);
        governor.execute(address(auraFarmer), data);
    }

    function test_setMaxWithdrawExpansionBPS() public {
        vm.expectRevert(OnlyL2Gov.selector);
        auraFarmer.setMaxLossWithdrawBps(0);

        bytes memory data = abi.encodeWithSelector(AuraFarmer.setMaxLossWithdrawBps.selector, 0);

        vm.prank(l2MessengerAlias);
        governor.execute(address(auraFarmer), data);

        assertEq(auraFarmer.maxLossWithdrawBps(), 0);

        data = abi.encodeWithSelector(AuraFarmer.setMaxLossWithdrawBps.selector, 10000);

        vm.expectRevert(WithdrawMaxLossTooHigh.selector);
        vm.prank(l2MessengerAlias);
        governor.execute(address(auraFarmer), data);
    }

    function test_setMaxLossTakeProfit() public {
        vm.expectRevert(OnlyL2Gov.selector);
        auraFarmer.setMaxLossTakeProfitBps(0);

        bytes memory data = abi.encodeWithSelector(AuraFarmer.setMaxLossTakeProfitBps.selector, 0);

        vm.prank(l2MessengerAlias);
        governor.execute(address(auraFarmer), data);

        assertEq(auraFarmer.maxLossTakeProfitBps(), 0);

        data = abi.encodeWithSelector(AuraFarmer.setMaxLossTakeProfitBps.selector, 10000);

        vm.expectRevert(TakeProfitMaxLossTooHigh.selector);
        vm.prank(l2MessengerAlias);
        governor.execute(address(auraFarmer), data);
    }

    function test_changeArbiFedL1() public {
        vm.expectRevert(OnlyL2Gov.selector);
        auraFarmer.changeArbiFedL1(address(0x70));
        
        assertEq(address(auraFarmer.arbiFedL1()), arbiFedL1);
       
        bytes memory data = abi.encodeWithSelector(AuraFarmer.changeArbiFedL1.selector, address(0x70));
        
        vm.startPrank(l2MessengerAlias); 
        governor.execute(address(auraFarmer), data);

        assertEq(address(auraFarmer.arbiFedL1()), address(0x70));
    }

    function test_changeArbiGovMessengerL1() public {
        vm.expectRevert(OnlyL2Gov.selector);
        auraFarmer.changeArbiGovMessengerL1(address(0x70));

        assertEq(address(auraFarmer.arbiGovMessengerL1()), address(arbiGovMessengerL1));
        
        bytes memory data = abi.encodeWithSelector(AuraFarmer.changeArbiGovMessengerL1.selector, address(0x70));
        
        vm.startPrank(l2MessengerAlias); 
        governor.execute(address(auraFarmer), data);

        assertEq(address(auraFarmer.arbiGovMessengerL1()), address(0x70));
    }
    function test_withdrawToL1ArbiFed() public {
        vm.prank(dolaUser);
        DOLAArbi.transfer(address(auraFarmer), dolaAmount);

        vm.expectRevert(OnlyL2Chair.selector);
        auraFarmer.withdrawToL1ArbiFed(dolaAmount);

        vm.prank(l2Chair);
        auraFarmer.withdrawToL1ArbiFed(dolaAmount);

        assertEq(DOLAArbi.balanceOf(address(auraFarmer)), 0);
    }

    
    function test_withdrawTokensToL1() public {
        vm.prank(usdcUser);
        USDCArbi.transfer(address(auraFarmer), usdcAmount);

        vm.expectRevert(OnlyL2Chair.selector);
        auraFarmer.withdrawToL1ArbiFed(usdcAmount);

        vm.prank(l2Chair);
        auraFarmer.withdrawTokensToL1(address(USDC),address(USDCArbi),address(2),usdcAmount);

        assertEq(DOLAArbi.balanceOf(address(auraFarmer)), 0);
    }
}   
