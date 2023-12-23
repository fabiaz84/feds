dola=0x7945b0A6674b175695e5d1D08aE1e6F13744Abb0; //baoUSDAddress
aura=0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF;
vault=0xBA12222222228d8Ba445958a75a0704d566BF2C8;
baseRewardPool=0x158e9aeE324B97b32DA71178D4761C6B18baE02a; //BaoUSDLUSDAuraDepositVault
booster=0xA57b8d98dAE62B26Ec3bcC4a365338157060B234;
chair=0xFC69e0a5823E2AfCBEb8a35d33588360F1496a00; //BaoDeployerMultisig
guardian=0xFC69e0a5823E2AfCBEb8a35d33588360F1496a00; //BaoDeployerMultisig
gov=0x3dFc49e5112005179Da613BdE5973229082dAc35; //BaoTreasuryMultisig
maxLossExpansion=10;
maxLossWithdraw=10;
maxLossTakeProfit=10;
poolId=0x7e9afd25f5ec0eb24d7d4b089ae7ecb9651c8b1f000000000000000000000511; //BalancerBPTAddress
forge create --rpc-url $1 \
    --constructor-args $dola $aura $vault $baseRewardPool $booster $chair $gov $maxLossExpansion $maxLossWithdraw $maxLossTakeProfit $poolId\
    --private-key $3 src/aura-fed/AuraFed.sol:AuraFed \
    --etherscan-api-key $2 \
    --verify
