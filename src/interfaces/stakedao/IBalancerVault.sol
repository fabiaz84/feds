// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IBalancerVault {
    function deposit(address _staker,uint256 _amount,bool _earn) external;

    function withdraw(uint256 _shares) external;
}
