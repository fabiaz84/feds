pragma solidity ^0.8.13;

import "src/interfaces/balancer/IVault.sol";
import "src/interfaces/IERC20.sol";

interface BPT is IERC20{
    function getPoolId() external view returns (bytes32);
}

contract BalancerMetapoolAdapter {
    
    uint constant BPS = 10_000;
    bytes32 immutable poolId;
    IERC20 immutable dola;
    IERC20 immutable bpt;
    IVault vault;
    IAsset[] assets = new IAsset[](0);
    uint dolaIndex = type(uint).max;
    
    constructor(bytes32 poolId_, address dola_, address vault_){
        poolId = poolId_;
        dola = IERC20(dola_);
        vault = IVault(vault_);
        (address bptAddress,) = vault.getPool(poolId_);
        bpt = IERC20(bptAddress);
        (IERC20[] memory tokens,,) = vault.getPoolTokens(poolId_);
        for(uint i; i<tokens.length; i++){
            assets.push(IAsset(address(tokens[i])));
            if(tokens[i] == dola){
                dolaIndex = i;
            }
        }
        require(dolaIndex < type(uint).max, "Underlying token not found");
        dola.approve(vault_, type(uint).max);
        bpt.approve(vault_, type(uint).max);
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

    function getUserDataExitExact(uint exactBptIn) internal view returns(bytes memory) {
        return abi.encode(1, exactBptIn, dolaIndex);
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

    function createExitExactPoolRequest(uint bptAmount, uint minDolaOut) internal view returns (IVault.ExitPoolRequest memory){
        IVault.ExitPoolRequest memory epr;
        epr.assets = assets;
        epr.minAmountsOut = new uint[](assets.length);
        epr.minAmountsOut[dolaIndex] = minDolaOut;
        epr.userData = getUserDataExitExact(bptAmount);
        epr.toInternalBalance = false;
        return epr;
    }

    function _deposit(uint dolaAmount, uint maxSlippage) internal returns(uint){
        //TODO: Make sure slippage is accounted for
        uint init = bpt.balanceOf(address(this));
        vault.joinPool(poolId, address(this), address(this), createJoinPoolRequest(dolaAmount));
        return bpt.balanceOf(address(this)) - init;
    }

    function _withdraw(uint dolaAmount, uint maxSlippage) internal returns(uint){
        //TODO: Calculate maxBPTin in a way that accounts for slippage
        //TODO: THIS IS CURRENTLY UNSAFE!
        uint init = dola.balanceOf(address(this));
        uint maxBPTin = type(uint).max;
        vault.exitPool(poolId, address(this), payable(address(this)), createExitPoolRequest(dolaAmount, maxBPTin));
        uint dolaOut = dola.balanceOf(address(this)) - init;
        require(dolaOut >= dolaAmount * BPS / maxSlippage,  "NOT ENOUGH DOLA RECEIVED");
        return dolaOut;
    }

    function _withdrawAll(uint expectedDolaAmount, uint maxSlippage) internal returns(uint){
        uint toWithdraw = bpt.balanceOf(address(this));
        vault.exitPool(poolId, address(this), payable(address(this)), createExitExactPoolRequest(expectedDolaAmount, expectedDolaAmount * BPS / maxSlippage));
    }

    function bptValue(address bpt) public view returns(uint){
        //TODO: Add function for taking aTokens into account
        bytes32 _poolId = BPT(bpt).getPoolId();
        (IERC20[] memory tokens, uint256[] memory balances, uint lastChange) = vault.getPoolTokens(_poolId);
        uint totalBalance;
        for(uint i; i < balances.length; i++){
            totalBalance += balances[i];
        }
        return totalBalance*10**18/IERC20(bpt).totalSupply();
    }

    function bptFromDola(uint dolaAmount) public view returns(uint) {
        revert("NOT IMPLEMENTED YET");
    }
}
