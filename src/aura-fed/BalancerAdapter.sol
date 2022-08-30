pragma solidity ^0.8.13;

import "src/interfaces/balancer/IVault.sol";
import "src/interfaces/IERC20.sol";

contract BalancerMetapoolAdapter {

    bytes32 immutable poolId;
    address immutable dola;
    address immutable bpt;
    IVault vault;
    IAsset[] assets = new IAsset[](0);
    uint dolaIndex = type(uint).max;
    
    constructor(bytes32 poolId_, address dola_, address vault_){
        poolId = poolId_;
        dola = dola_;
        vault = IVault(vault_);
        (bpt,) = vault.getPool(poolId_);
        (IERC20[] memory tokens,,) = vault.getPoolTokens(poolId_);
        for(uint i; i<tokens.length; i++){
            assets.push(IAsset(address(tokens[i])));
            if(address(tokens[i]) == dola_){
                dolaIndex = i;
            }
        }
        require(dolaIndex < type(uint).max, "Underlying token not found");
        IERC20(dola).approve(vault_, type(uint).max);
        IERC20(bpt).approve(vault_, type(uint).max);
    }

    function getUserDataExactInDola(uint amountIn) internal view returns(bytes memory) {
        uint[] memory amounts = new uint[](assets.length);
        amounts[dolaIndex] = amountIn;
        return abi.encode(1, amounts);
    }

    function getUserDataExactInBPT(uint amountIn) internal view returns(bytes memory) {
        uint[] memory amounts = new uint[](assets.length);
        amounts[dolaIndex] = amountIn;
        return abi.encode(0, amounts);
    }

    function getUserDataCustomExit(uint exactDolaOut, uint maxBPTin) internal view returns(bytes memory) {
        uint[] memory amounts = new uint[](assets.length);
        amounts[dolaIndex] = exactDolaOut;
        return abi.encode(2, amounts, maxBPTin);
    } 

    function createJoinPoolRequest(uint dolaAmount) internal view returns(IVault.JoinPoolRequest memory){
        IVault.JoinPoolRequest memory jpr;
        jpr.assets = assets;
        jpr.maxAmountsIn = new uint[](assets.length);
        jpr.maxAmountsIn[dolaIndex] = dolaAmount;
        jpr.userData = getUserDataExactInDola(dolaAmount);
        jpr.fromInternalBalance = false;
        return jpr;
    }

    function createExitPoolRequest(uint dolaAmount, uint maxBPTin) internal view returns (IVault.ExitPoolRequest memory){
        IVault.ExitPoolRequest memory epr;
        epr.assets = assets;
        epr.minAmountsOut = new uint[](assets.length);
        epr.minAmountsOut[dolaIndex] = dolaAmount;
        epr.userData = getUserDataCustomExit(dolaAmount, maxBPTin);
        epr.toInternalBalance = false;
        return epr;
    }

    function _deposit(uint dolaAmount, uint maxSlippage) internal {
        //TODO: Make sure slippage is accounted for
        vault.joinPool(poolId, address(this), address(this), createJoinPoolRequest(dolaAmount));
    }

    function _withdraw(uint dolaAmount, uint maxSlippage) internal {
        //TODO: Calculate maxBPTin in a way that accounts for slippage
        //TODO: THIS IS CURRENTLY UNSAFE!
        uint maxBPTin = type(uint).max;
        vault.exitPool(poolId, address(this), payable(address(this)), createExitPoolRequest(dolaAmount, maxBPTin));
    }
}
