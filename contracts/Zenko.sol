// SPDX-License-Identifier: GPL-2.0-or-later
/*
 ▄▄▄▄▄▄   ▄███▄      ▄   █  █▀ ████▄ 
▀   ▄▄▀   █▀   ▀      █  █▄█   █   █ 
 ▄▀▀   ▄▀ ██▄▄    ██   █ █▀▄   █   █ 
 ▀▀▀▀▀▀   █▄   ▄▀ █ █  █ █  █  ▀████ 
          ▀███▀   █  █ █   █         
                  █   ██  ▀       */
/// 🦊🌾 Special thanks to Keno / Boring / Gonpachi / Karbon for review and continued inspiration.
pragma solidity 0.8.6;

interface IERC20 {} interface IBentoHelper {
    function toAmount(
        IERC20 token,
        uint256 share,
        bool roundUp
    ) external view returns (uint256 amount);

    function toShare(
        IERC20 token,
        uint256 amount,
        bool roundUp
    ) external view returns (uint256 share);
}

interface ICompoundHelper {
    function decimals() external view returns (uint8);
    function underlying() external view returns (address);
    function getCash() external view returns (uint256);
    function totalBorrows() external view returns (uint256);
    function totalReserves() external view returns (uint256);
    function totalSupply() external view returns (uint256);

}

interface IKashiHelper {
    function asset() external view returns (IERC20);
    function totalAsset() external view returns (Rebase memory);
    function totalBorrow() external view returns (Rebase memory);
    struct Rebase {
        uint128 elastic;
        uint128 base;
    }
}

/// @notice Helper for Inari SushiZap calculations.
contract Zenko {
    IBentoHelper constant bento = IBentoHelper(0xF5BCE5077908a1b7370B9ae04AdC565EBd643966); // BENTO vault contract (multinet)
    
    // **** BENTO 
    function toBento(IERC20 token, uint256 amount) external view returns (uint256 share) {
        share = bento.toShare(token, amount, false);
    }
    
    function fromBento(IERC20 token, uint256 share) external view returns (uint256 amount) {
        amount = bento.toAmount(token, share, false);
    }
    
    // **** COMPOUND/CREAM
    function toCompound(ICompoundHelper cToken, uint256 underlyingAmount) external view returns (uint256 cTokenAmount) { 
        uint256 exchangeRate = cToken.getCash() + cToken.totalBorrows() - cToken.totalReserves() / cToken.totalSupply();
        ICompoundHelper underlying = ICompoundHelper(cToken.underlying());
        cTokenAmount = underlyingAmount / exchangeRate * 10**(underlying.decimals() - cToken.decimals());
    }
    
    function fromCompound(ICompoundHelper cToken, uint256 cTokenAmount) external view returns (uint256 underlyingAmount) {
        uint256 exchangeRate = cToken.getCash() + cToken.totalBorrows() - cToken.totalReserves() / cToken.totalSupply();
        ICompoundHelper underlying = ICompoundHelper(cToken.underlying());
        underlyingAmount = cTokenAmount * exchangeRate / 10**(underlying.decimals());
    }
    
    // **** KASHI ASSET
    function toKashi(IKashiHelper kmToken, uint256 underlyingAmount) external view returns (uint256 fraction) {
        IERC20 token = kmToken.asset();
        uint256 share = bento.toShare(token, underlyingAmount, false);
        uint256 allShare = kmToken.totalAsset().elastic + bento.toShare(token, kmToken.totalBorrow().elastic, true);
        fraction = allShare == 0 ? share : share * kmToken.totalAsset().base / allShare;
    }
    
    function fromKashi(IKashiHelper kmToken, uint256 kmAmount) external view returns (uint256 share) {
        uint256 allShare = kmToken.totalAsset().elastic + bento.toShare(kmToken.asset(), kmToken.totalBorrow().elastic, true);
        share = kmAmount * allShare / kmToken.totalAsset().base;
    }
}
