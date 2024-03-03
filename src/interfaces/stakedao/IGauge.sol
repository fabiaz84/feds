// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IGauge {
    function balanceOf(address account) external view returns (uint256);
}
