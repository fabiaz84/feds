#!/bin/zsh

# Define the initial addresses
dola="0xf4edfad26EE0D23B69CA93112eccE52704E0006f"
aura="0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF"
vault="0xBA12222222228d8Ba445958a75a0704d566BF2C8"
dolaBptRewardPool="0xc8FC8aC325d941C31655C62169DD47778129BE63"
bpt="0x1A44E35d5451E0b78621A1B3e7a53DFaA306B1D0"
booster="0xA57b8d98dAE62B26Ec3bcC4a365338157060B234"
chair="0xFC69e0a5823E2AfCBEb8a35d33588360F1496a00"
guardian="0xFC69e0a5823E2AfCBEb8a35d33588360F1496a00"
gov="0x3dFc49e5112005179Da613BdE5973229082dAc35"

# Define other parameters
maxLossExpansion=10
maxLossWithdraw=10
maxLossTakeProfit=10
poolId="0x1a44e35d5451e0b78621a1b3e7a53dfaa306b1d000000000000000000000051b"

# Concatenate the constructor arguments into a single string
constructorArgs="($dola, $aura, $vault, $dolaBptRewardPool, $bpt, $booster, $chair, $guardian, $gov)"

# Run the forge create command
forge create \
    --rpc-url $1 \
    --constructor-args $constructorArgs $maxLossExpansion $maxLossWithdraw $maxLossTakeProfit $poolId \
    --private-key $3 \
    --etherscan-api-key $2 \
    --verify \
    src/aura-fed/AuraFed.sol:AuraFed
