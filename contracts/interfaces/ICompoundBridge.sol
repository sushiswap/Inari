// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

/// @notice Interface for depositing into and withdrawing from Compound finance protocol.
interface ICompoundBridge {
    function underlying() external view returns (address);
    function mint(uint mintAmount) external returns (uint);
    function redeem(uint redeemTokens) external returns (uint);
}
