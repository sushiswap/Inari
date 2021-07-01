// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

/// @notice Interface for SUSHI MasterChef v2.
interface IMasterChefV2 {
    function lpToken(uint256 pid) external view returns (IERC20);
    function deposit(uint256 pid, uint256 amount, address to) external;
}
