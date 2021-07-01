// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

/// @notice Interface for wrapped ether v9.
interface IWETH {
    function deposit() external payable;
}
