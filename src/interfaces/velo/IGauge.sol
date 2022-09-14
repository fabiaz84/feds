pragma solidity ^0.8.13;

interface IGauge {
    function deposit(uint amount, uint tokenId) external;
    function getReward(address account, address[] memory tokens) external;
    function withdraw(uint shares) external;
    function balanceOf(address account) external returns (uint);
}