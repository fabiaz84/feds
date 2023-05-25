gov=0x926dF14a23BE491164dCF93f4c468A50ef659D5B;
chair=0x8F97cCA30Dbe80e7a8B462F1dD1a51C32accDfC8;
guardian=0xE3eD95e130ad9E15643f5A5f232a3daE980784cd;
veloFarmer=0xFED67cC40E9C5934F157221169d772B328cb138E;
forge create --rpc-url $1 \
    --constructor-args $gov $chair $guardian $veloFarmer \
    --private-key $3 \
    --etherscan-api-key $2 \
    --verify \
    src/velo-fed/VeloFarmerMessenger.sol:VeloFarmerMessenger
