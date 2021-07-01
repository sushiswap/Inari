// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

/// @notice Interface for Dai Stablecoin (DAI) `permit()` primitive.
interface IDaiPermit {
    function permit(
        address holder,
        address spender,
        uint256 nonce,
        uint256 expiry,
        bool allowed,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}
