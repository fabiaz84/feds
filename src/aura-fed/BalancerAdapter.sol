pragma solidity ^0.8.13;

import "src/interfaces/balancer/IVault.sol";
import "src/interfaces/IERC20.sol";

interface IBPT is IERC20{
    function getPoolId() external view returns (bytes32);
    function getRate() external view returns (uint256);
}

interface IBABP is IERC20{
    function getMainToken() external view returns (address);
    function getWrappedToken() external view returns (address);
}

interface IBalancerHelper{
    function queryExit(bytes32 poolId, address sender, address recipient, IVault.ExitPoolRequest memory erp) external returns (uint256 bptIn, uint256[] memory amountsOut);
    function queryJoin(bytes32 poolId, address sender, address recipient, IVault.JoinPoolRequest memory jrp) external returns (uint256 bptOut, uint256[] memory amountsIn);
}


contract BalancerMetapoolAdapter {
    
    uint constant BPS = 10_000;
    bytes32 immutable poolId;
    bytes32 bbaUSDpoolId;
    IERC20 immutable dola;
    IBPT immutable bbAUSD = IBPT(0xA13a9247ea42D743238089903570127DdA72fE44);
    IBalancerHelper helper = IBalancerHelper(0x5aDDCCa35b7A0D07C74063c48700C8590E87864E);
    IBPT immutable bpt = IBPT(0x5b3240B6BE3E7487d61cd1AFdFC7Fe4Fa1D81e64);
    IVault vault;
    IAsset[] assets = new IAsset[](0);
    uint dolaIndex = type(uint).max;
    
    event log_addr(address);

    constructor(bytes32 poolId_, address dola_, address vault_){
        poolId = poolId_;
        bbaUSDpoolId = bbAUSD.getPoolId();
        dola = IERC20(dola_);
        vault = IVault(vault_);
        //(address bptAddress, IVault.PoolSpecialization specialization) = vault.getPool(poolId_);
        (IERC20[] memory tokens,,) = vault.getPoolTokens(bpt.getPoolId());
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

    function createExitPoolRequest(uint index, uint dolaAmount, uint maxBPTin) internal view returns (IVault.ExitPoolRequest memory){
        IVault.ExitPoolRequest memory epr;
        epr.assets = assets;
        epr.minAmountsOut = new uint[](assets.length);
        epr.minAmountsOut[index] = dolaAmount;
        epr.userData = getUserDataCustomExit(dolaAmount, maxBPTin);
        epr.toInternalBalance = false;
        return epr;
    }

    function createExitExactPoolRequest(uint index, uint bptAmount, uint minDolaOut) internal view returns (IVault.ExitPoolRequest memory){
        IVault.ExitPoolRequest memory epr;
        epr.assets = assets;
        epr.minAmountsOut = new uint[](assets.length);
        epr.minAmountsOut[index] = minDolaOut;
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
        vault.exitPool(poolId, address(this), payable(address(this)), createExitPoolRequest(dolaIndex, dolaAmount, maxBPTin));
        uint dolaOut = dola.balanceOf(address(this)) - init;
        require(dolaOut >= dolaAmount * BPS / maxSlippage,  "NOT ENOUGH DOLA RECEIVED");
        return dolaOut;
    }

    function _withdrawAll(uint expectedDolaAmount, uint maxSlippage) internal returns(uint){
        uint toWithdraw = bpt.balanceOf(address(this));
        vault.exitPool(poolId, address(this), payable(address(this)), createExitExactPoolRequest(dolaIndex, expectedDolaAmount, expectedDolaAmount * BPS / maxSlippage));
    }

    function _outFromExactIn(bytes32 poolId, uint lpAmountIn, uint indexOut) internal returns(uint) {
        (,uint[] memory amountsOut) = helper.queryExit(poolId, address(this), address(this), createExitExactPoolRequest(indexOut, lpAmountIn, 0));
         return amountsOut[indexOut];
    }

    function _bbaUSDValue(uint amount, bool optimistic) internal returns(uint){
        //TODO: Find better way to ensure that the indexes we're hitting are DAI, USDC and USDT
        uint out = optimistic ? 0 : type(uint).max;
        (IERC20[] memory aaveLinearTokens,,) = vault.getPoolTokens(bbaUSDpoolId);
        for(uint i; i < 3; i++){
            uint specificOut = _outFromExactIn(bbaUSDpoolId, amount, i);
            uint mainOut = _outFromExactIn(IBPT(address(aaveLinearTokens[i])).getPoolId(), specificOut, i);
            if(optimistic ? mainOut > out : mainOut < out){
                out = specificOut;
            }
        }
        return out;
    }

    function _bptUSDValue(uint amount, bool optimistic) internal returns(uint){
        uint dolaValue = _outFromExactIn(poolId, amount, 0);
        uint bbaUSDAmount = _outFromExactIn(poolId, amount, 1);
        uint bbaUsdValue = _bbaUSDValue(bbaUSDAmount, optimistic);
        if(optimistic){
            return dolaValue > bbaUsdValue ? dolaValue : bbaUsdValue;
        } else {
            return dolaValue > bbaUsdValue ? bbaUsdValue : dolaValue;
        }
    }

    function bptNeededForDola(uint dolaAmount) public returns(uint) {
        (,uint[] memory amountsOut) = helper.queryExit(poolId, address(this), address(this), createExitPoolRequest(dolaIndex, dolaAmount, 0));
        return amountsOut[dolaIndex];
    }
}
