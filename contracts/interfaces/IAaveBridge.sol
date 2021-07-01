// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

/// @notice Interface for depositing into and withdrawing from Aave lending pool.
interface IAaveBridge {
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);

    function deposit( 
        address asset, 
        uint256 amount, 
        address onBehalfOf, 
        uint16 referralCode
    ) external;

    function withdraw( 
        address token, 
        uint256 amount, 
        address destination
    ) external;
}
