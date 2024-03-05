#!/bin/zsh

# Define the initial addresses
dola="0x7945b0A6674b175695e5d1D08aE1e6F13744Abb0"
bal="0xba100000625a3754423978a60c9317c58a424e3D"
std="0x73968b9a57c6E53d41345FD57a6E6ae27d6CDB2F"
vault="0xBA12222222228d8Ba445958a75a0704d566BF2C8"
bpt="0x7E9AfD25F5Ec0eb24d7d4b089Ae7EcB9651c8b1F"
balancerVault="0xd9663a5e08f0b3db295c5346c1b52677b7398585"
baoGauge="0x1A44E35d5451E0b78621A1B3e7a53DFaA306B1D0"
sdbaousdGauge="0xC6A0B204E28C05838b8B1C36f61963F16eCD64C4"
rewards="0x633120100e108F03aCe79d6C78Aac9a56db1be0F"
chair="0xFC69e0a5823E2AfCBEb8a35d33588360F1496a00"
guardian="0xFC69e0a5823E2AfCBEb8a35d33588360F1496a00"
gov="0x3dFc49e5112005179Da613BdE5973229082dAc35"

# Define other parameters
maxLossExpansion=10
maxLossWithdraw=10
maxLossTakeProfit=10
poolId="0x7e9afd25f5ec0eb24d7d4b089ae7ecb9651c8b1f000000000000000000000511"

# Concatenate the constructor arguments into a single string
constructorArgs="($dola, $bal, $std, $vault, $bpt, $balancerVault, $baoGauge, $rewards, $chair, $guardian, $gov)"

# Run the forge create command
forge create \
    --rpc-url $1 \
    --constructor-args $constructorArgs $maxLossExpansion $maxLossWithdraw $maxLossTakeProfit $poolId \
    --private-key $3 \
    --etherscan-api-key $2 \
    --verify \
    src/stakedao-fed/StakeDaoFed.sol:StakeDaoFed
