// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

/// @notice Interface for depositing into and withdrawing from SushiBar.
interface ISushiBarBridge { 
    function enter(uint256 amount) external;
    function leave(uint256 share) external;
}
