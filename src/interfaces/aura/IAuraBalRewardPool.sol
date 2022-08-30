// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

interface IAuraBalRewardPool {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function lastTimeRewardApplicable() external view returns (uint256);

    function rewardPerToken() external view returns (uint256);

    function earned(address account) external view returns (uint256);

    function stake(uint256 _amount) external returns (bool);

    function stakeAll() external returns (bool);

    function stakeFor(address _for, uint256 _amount) external updateReward(_for) returns (bool);

    function withdraw(uint256 amount, bool claim, bool lock) external returns (bool);

    /**
     * @dev Gives a staker their rewards
     * @param _lock Lock the rewards? If false, takes a 20% haircut
     */
    function getReward(bool _lock) external updateReward(msg.sender) returns (bool);

    /**
     * @dev Forwards to the penalty forwarder for distro to Aura Lockers
     */
    function forwardPenalty() external;
}
