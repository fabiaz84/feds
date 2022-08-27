pragma solidity ^0.8.13;

import "src/interfaces/balancer/IVault.sol";

contract BalancerMetapoolAdapter {

    struct ExitPoolRequest {
        IAsset[] assets;
        uint[] maxAmountsIn;
        bytes userData;
        bool toInternalBalance;
    }

    bytes32 immutable poolId;
    address immutable dola;
    IAsset[] assets;
    IVault vault;
    uint dolaIndex;

    constructor(bytes32 poolId_, address dola_, address vault_){
        poolId = poolId_;
        dola = dola_;
        vault = IVault(vault_);
        (IERC20[] memory tokens,,) = vault.getPoolTokens(poolId_);
        for(uint i; i<tokens.length; i++){
            assets.push(IAsset(address(tokens[i])));
            if(address(tokens[i]) == dola_){
                dolaIndex = i;
            }
        }
    }

    function getUserDataExactInDola(uint amountIn, uint index) internal view returns(bytes memory) {
        uint[] memory amounts = new uint[](assets.length);
        amounts[index] = amountIn;
        return abi.encode(1, amounts);
    }

    function getUserDataExactInBPT(uint amountIn, uint index) internal view returns(bytes memory) {
        uint[] memory amounts = new uint[](assets.length);
        amounts[index] = amountIn;
        return abi.encode(0, amounts);
    }

    function createJoinPoolRequest(uint dolaAmount) internal view returns(IVault.JoinPoolRequest memory){
        IVault.JoinPoolRequest memory jpr;
        jpr.assets = assets;
        jpr.maxAmountsIn[dolaIndex] = dolaAmount;
        jpr.userData = getUserDataExactInDola(dolaAmount, dolaIndex);
        jpr.fromInternalBalance = false;
        return jpr;
    }

    function deposit(uint dolaAmount, uint maxSlippage) internal returns(uint) {
        //TODO: Make sure slippage is accounted for
        vault.joinPool(poolId, address(this), address(this), createJoinPoolRequest(dolaAmount));
    }

}
