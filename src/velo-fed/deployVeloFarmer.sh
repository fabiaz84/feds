controller=0x788C3Efc8182393915e216174a03cD81395f8C7a;
bridge=0x4200000000000000000000000000000000000010;
forge create --rpc-url $1 \
    --constructor-args $controller $controller $controller $controller $controller $bridge $controller 0 0 0 \
    --private-key $3 \
    --etherscan-api-key $2 \
    --verify \
    src/velo-fed/VeloFarmerV2.sol:VeloFarmerV2
