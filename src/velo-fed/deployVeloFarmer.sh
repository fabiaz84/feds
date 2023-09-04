gov=0x257D2836c8f5797581740543F853403b81C44b5A;
chair=0x257D2836c8f5797581740543F853403b81C44b5A;
l2chair=0x9f9Fa2C6b432689Dcd4E3ad55f86FdE6c03694EE;
treasury=0xa283139017a2f5BAdE8d8e25412C600055D318F8;
guardian=0x257D2836c8f5797581740543F853403b81C44b5A
bridge=0x4200000000000000000000000000000000000010;
optiFed=0xfEd533e0Ec584D6FF40281a7850c4621D258b43d;
maxDolaToUsdcSlip=30;
maxUsdcToDolaSlip=30;
maxLiquiditySlip=55;
forge create --rpc-url $1 \
    --constructor-args $gov $chair $l2chair $treasury $guardian $bridge $optiFed $maxDolaToUsdcSlip $maxUsdcToDolaSlip $maxLiquiditySlip \
    --private-key $3 \
    --etherscan-api-key $2 \
    --verify \
    src/velo-fed/VeloFarmerV2.sol:VeloFarmerV2
