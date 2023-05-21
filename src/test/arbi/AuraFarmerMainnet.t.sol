// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "ds-test/test.sol";
import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IDola} from "src/interfaces/velo/IDola.sol";
import {ArbiGovMessengerL1} from "src/arbi-fed/ArbiGovMessengerL1.sol";
import {AuraFarmer} from "src/arbi-fed/AuraFarmer.sol";
import {IInbox} from "arbitrum-nitro/contracts/src/bridge/IInbox.sol";
import "src/interfaces/aura/IAuraBalRewardPool.sol";
import "src/interfaces/balancer/IComposablePoolFactory.sol";
import "src/interfaces/balancer/IVault.sol";

contract RateProvider {
    function getRate() external view returns (uint256) {
        return 1e18;
    }
}

interface IGaugeFactory {
    function create(address _pool) external returns (address);
}

interface IAuraBooster {
    function addPool(address _pool, address _gauge, uint256 _stashVersion) external returns (bool);
}

interface IGaugeAdder {
    function addEthereumGauge(address _gauge) external;
}

interface IGaugeController {
    function add_gauge(address _gauge, int128 _type, uint256 _weight) external;
}

contract AuraFarmerTest is Test {
    //Tokens
    IDola public DOLA = IDola(0x865377367054516e17014CcdED1e7d814EDC9ce4);
    IERC20 public USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 bpt = IERC20(0xFf4ce5AAAb5a627bf82f4A571AB1cE94Aa365eA6); // USDC-DOLA bal pool
    IERC20 bal = IERC20(0xba100000625a3754423978a60c9317c58a424e3D);
    IERC20 aura = IERC20(0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF);
    IVault vault = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    IAuraBalRewardPool baseRewardPool =
        IAuraBalRewardPool(0x99653d46D52eE41c7b35cbAd1aC408A00bad6A76);
    address booster = 0xA57b8d98dAE62B26Ec3bcC4a365338157060B234;
    address gauge;
    address gaugeAdder = 0x5efBb12F01f27F0E020565866effC1dA491E91A4;
    address gaugeController = 0xC128468b7Ce63eA702C1f104D55A2566b13D3ABD;

    IGaugeFactory gaugeFactory = IGaugeFactory(0x4E7bBd911cf1EFa442BC1b2e9Ea01ffE785412EC);
   
    bytes32 salt =
        bytes32(
            0xff4ce5aaab5a627bf82f4a571ab1ce94aa365ea6000200000000000000000426
        );

    IComposablePoolFactory composablePoolFactory =
        IComposablePoolFactory(0xfADa0f4547AB2de89D1304A668C39B3E09Aa7c76);

    ComposableStablePool pool;
    RateProvider rateProvider;
    // Values taken from AuraFed for USDC-DOLA 0x1CD24E3FBae88BECbaFED4b8Cda765D1e6e3BC03
    uint maxLossExpansion = 13;
    uint maxLossWithdraw = 10;
    uint maxLossTakeProfit = 10;


    bytes32 poolId;// Composable stable pool id for DOLA-USDC
    
    //address chair = address(this);
    address l2Chair = address(0x69);
    address l2Gov = address(0x420);
    address gov = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;
    address usdcUser = 0xDa9CE944a37d218c3302F6B82a094844C6ECEb17;
    
    //Numbas
    uint dolaAmount = 100_000e18;
    uint usdcAmount = 100_000e6;
    uint initDolaAmount = 10_000_000e18;
    uint initUsdcAmount = 10_000_000e6;

    //Feds
    AuraFarmer auraFarmer;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 17228840);

        // Create balancer pool for DOLA-USDC

        rateProvider = new RateProvider();

        IRateProvider[] memory rateProviders = new IRateProvider[](2);
        rateProviders[0] = IRateProvider(address(rateProvider));
        rateProviders[1] = IRateProvider(address(rateProvider));

        uint256[] memory tokenRateCacheDurations = new uint256[](2);
        tokenRateCacheDurations[0] = 0;
        tokenRateCacheDurations[1] = 0;

        bool[] memory exemptFromYieldProtocolFeeFlags = new bool[](2);
        exemptFromYieldProtocolFeeFlags[0] = false;
        exemptFromYieldProtocolFeeFlags[1] = false;

        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = IERC20(address(DOLA));
        tokens[1] = USDC;

        pool = composablePoolFactory.create(
            "DOLA-USDC",
            "DOLA-USDC",
            tokens,
            10,
            rateProviders,
            tokenRateCacheDurations,
            exemptFromYieldProtocolFeeFlags,
            1e15,
            address(this),
            salt
        );

        console.log("Pool address: %s", address(pool));

        poolId = IComposablePool(address(pool)).getPoolId();
        
        console.logBytes32(poolId);

        // Add liquidity to balancer pool
        vm.prank(gov);
        DOLA.mint(address(this), initDolaAmount);
        vm.prank(usdcUser);
        USDC.transfer(address(this), initUsdcAmount);

        DOLA.approve(address(vault), initDolaAmount);
        USDC.approve(address(vault), initUsdcAmount);

         (address[] memory poolTokens,,) = vault.getPoolTokens(poolId);
        console.log("Tokens: %s", poolTokens[0]);
        console.log("Tokens: %s", poolTokens[1]);
        console.log("Tokens: %s", poolTokens[2]);
    
        IVault.JoinPoolRequest memory request =
            IVault.JoinPoolRequest({
                assets: new IAsset[](3),
                maxAmountsIn: new uint256[](3),
                userData: "",
                fromInternalBalance: false
            });

        request.assets[0] = IAsset(address(pool));
        request.assets[1] = IAsset(address(DOLA));
        request.assets[2] = IAsset(address(USDC));
       
        request.maxAmountsIn[0] = 2**(111);
        request.maxAmountsIn[1] = initDolaAmount;
        request.maxAmountsIn[2] = initUsdcAmount;

        request.userData = abi.encode(IVault.JoinKind.INIT, request.maxAmountsIn);
        
        vault.joinPool(poolId, address(this), address(this), request);

        gauge = IGaugeFactory(gaugeFactory).create(address(pool));
        console.log("Gauge address: %s", gauge);
        
        vm.prank(0x8F42aDBbA1B16EaAE3BB5754915E0D06059aDd75);
        IGaugeController(gaugeController).add_gauge(gauge,1,0);

        // vm.prank(0xc38c5f97B34E175FFd35407fc91a937300E33860); 
        // IGaugeAdder(gaugeAdder).addEthereumGauge(gauge);

        vm.prank(0x2c809Ec701C088099c911AF9DdfA4A1Db6110F3c); // Booster Pool Manager
        bool added = IAuraBooster(booster).addPool(address(pool), gauge, 3);
        console.log(added);


        // Deploy Aura Farmer
        auraFarmer = new AuraFarmer(
            address(DOLA),
            address(vault),
            address(baseRewardPool),
            booster,
            l2Chair,
            l2Gov,
            maxLossExpansion,
            maxLossWithdraw,
            maxLossTakeProfit,
            poolId
        );


    }

    function test_deposit() public {
    
        vm.prank(gov);
        DOLA.mint(address(auraFarmer), dolaAmount);

        vm.prank(l2Chair);
        auraFarmer.deposit(dolaAmount);
    }

}   
