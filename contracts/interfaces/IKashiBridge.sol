// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

/// @notice Interface for depositing and withdrawing assets from KASHI.
interface IKashiBridge {
    function asset() external returns (IERC20);
    
    function addAsset(
        address to,
        bool skim,
        uint256 share
    ) external returns (uint256 fraction);
    
    function removeAsset(address to, uint256 fraction) external returns (uint256 share);
}
