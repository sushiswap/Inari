// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import "./BoringBatchable.sol";
import "./libraries/Babylonian.sol";
import "./interfaces/ISushiSwap.sol";
import "./interfaces/IWETH.sol";
import "./SushiZap.sol";
import "./interfaces/IAaveBridge.sol";
import "./interfaces/IBentoBridge.sol";
import "./interfaces/ICompoundBridge.sol";
import "./interfaces/IKashiBridge.sol";
import "./interfaces/ISushiBarBridge.sol";
import "./interfaces/IMasterChefV2.sol";

/// @notice Contract that batches SUSHI staking and DeFi strategies - V1 'iroirona'.
contract InariV1 is BoringBatchableWithDai, SushiZap {
    using SafeMath for uint256;
    using BoringERC20 for IERC20;
    
    IERC20 constant sushiToken = IERC20(0x6B3595068778DD592e39A122f4f5a5cF09C90fE2); // SUSHI token contract
    address constant sushiBar = 0x8798249c2E607446EfB7Ad49eC89dD1865Ff4272; // xSUSHI staking contract for SUSHI
    ISushiSwap constant sushiSwapSushiETHPair = ISushiSwap(0x795065dCc9f64b5614C407a6EFDC400DA6221FB0); // SUSHI/ETH pair on SushiSwap
    IMasterChefV2 constant masterChefv2 = IMasterChefV2(0xEF0881eC094552b2e128Cf945EF17a6752B4Ec5d); // SUSHI MasterChef v2 contract
    IAaveBridge constant aave = IAaveBridge(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9); // AAVE lending pool contract for xSUSHI staking into aXSUSHI
    IERC20 constant aaveSushiToken = IERC20(0xF256CC7847E919FAc9B808cC216cAc87CCF2f47a); // aXSUSHI staking contract for xSUSHI
    IBentoBridge constant bento = IBentoBridge(0xF5BCE5077908a1b7370B9ae04AdC565EBd643966); // BENTO vault contract
    address constant crSushiToken = 0x338286C0BC081891A4Bda39C7667ae150bf5D206; // crSUSHI staking contract for SUSHI
    address constant crXSushiToken = 0x228619CCa194Fbe3Ebeb2f835eC1eA5080DaFbb2; // crXSUSHI staking contract for xSUSHI
    address constant wETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // ETH wrapper contract v9
    
    /// @notice Initialize this Inari contract.
    constructor() {
        bento.registerProtocol(); // register this contract with BENTO
    }
    
    /// @notice Helper function to approve this contract to spend tokens and enable strategies.
    function bridgeToken(IERC20[] calldata token, address[] calldata to) external {
        for (uint256 i = 0; i < token.length; i++) {
            token[i].safeApprove(to[i], type(uint256).max); // max approve `to` spender to pull `token` from this contract
        }
    }

    /**********
    TKN HELPERS 
    **********/
    function withdrawToken(IERC20 token, address to, uint256 amount) external {
        token.safeTransfer(to, amount); 
    }
    
    function withdrawTokenBalance(IERC20 token, address to) external {
        token.safeTransfer(to, token.safeBalanceOfSelf()); 
    }

    /***********
    SUSHI HELPER 
    ***********/
    /// @notice Stake SUSHI local balance into xSushi for benefit of `to` by call to `sushiBar`.
    function stakeSushiBalance(address to) external {
        ISushiBarBridge(sushiBar).enter(sushiToken.safeBalanceOfSelf()); // stake local SUSHI into `sushiBar` xSUSHI
        IERC20(sushiBar).safeTransfer(to, IERC20(sushiBar).safeBalanceOfSelf()); // transfer resulting xSUSHI to `to`
    }
    
    /***********
    CHEF HELPERS 
    ***********/
    function depositToMasterChefv2(uint256 pid, uint256 amount, address to) external {
        masterChefv2.deposit(pid, amount, to);
    }
    
    function balanceToMasterChefv2(uint256 pid, address to) external {
        IERC20 lpToken = masterChefv2.lpToken(pid);
        masterChefv2.deposit(pid, lpToken.safeBalanceOfSelf(), to);
    }
    
    /// @notice Liquidity zap into CHEF.
    function zapToMasterChef(
        address to,
        address _FromTokenContractAddress,
        uint256 _amount,
        uint256 _minPoolTokens,
        uint256 pid,
        address _swapTarget,
        bytes calldata swapData
    ) external payable returns (uint256) {
        uint256 toInvest = _pullTokens(
            _FromTokenContractAddress,
            _amount
        );
        IERC20 _pairAddress = masterChefv2.lpToken(pid);
        uint256 LPBought = _performZapIn(
            _FromTokenContractAddress,
            address(_pairAddress),
            toInvest,
            _swapTarget,
            swapData
        );
        require(LPBought >= _minPoolTokens, "ERR: High Slippage");
        emit ZapIn(to, address(_pairAddress), LPBought);
        masterChefv2.deposit(pid, LPBought, to);
        return LPBought;
    }
    
    /************
    KASHI HELPERS 
    ************/
    /************
    KASHI HELPERS 
    ************/
    function assetToKashi(IKashiBridge kashiPair, address to, uint256 amount) external returns (uint256 fraction) {
        IERC20 asset = kashiPair.asset();
        asset.safeTransferFrom(msg.sender, address(bento), amount);
        IBentoBridge(bento).deposit(asset, address(bento), address(kashiPair), amount, 0); 
        fraction = kashiPair.addAsset(to, true, amount);
    }
    
    function assetToKashiChef(uint256 pid, uint256 amount, address to) external returns (uint256 fraction) {
        address kashiPair = address(masterChefv2.lpToken(pid));
        IERC20 asset = IKashiBridge(kashiPair).asset();
        asset.safeTransferFrom(msg.sender, address(bento), amount);
        IBentoBridge(bento).deposit(asset, address(bento), address(kashiPair), amount, 0); 
        fraction = IKashiBridge(kashiPair).addAsset(address(this), true, amount);
        masterChefv2.deposit(pid, fraction, to);
    }
    
    function assetBalanceToKashi(IKashiBridge kashiPair, address to) external returns (uint256 fraction) {
        IERC20 asset = kashiPair.asset();
        uint256 balance = asset.safeBalanceOfSelf();
        IBentoBridge(bento).deposit(asset, address(bento), address(kashiPair), balance, 0); 
        fraction = kashiPair.addAsset(to, true, balance);
    }
    
    function assetBalanceToKashiChef(uint256 pid, address to) external returns (uint256 fraction) {
        address kashiPair = address(masterChefv2.lpToken(pid));
        IERC20 asset = IKashiBridge(kashiPair).asset();
        uint256 balance = asset.safeBalanceOfSelf();
        IBentoBridge(bento).deposit(asset, address(bento), address(kashiPair), balance, 0); 
        fraction = IKashiBridge(kashiPair).addAsset(address(this), true, balance);
        masterChefv2.deposit(pid, fraction, to);
    }

    function assetBalanceFromKashi(address kashiPair, address to) external returns (uint256 share) {
        share = IKashiBridge(kashiPair).removeAsset(to, IERC20(kashiPair).safeBalanceOfSelf());
    }
    
    /// @notice Liquidity zap into KASHI.
    function zapToKashi(
        address to,
        address _FromTokenContractAddress,
        IKashiBridge kashiPair,
        uint256 _amount,
        uint256 _minPoolTokens,
        address _swapTarget,
        bytes calldata swapData
    ) external payable returns (uint256 fraction) {
        uint256 toInvest = _pullTokens(
            _FromTokenContractAddress,
            _amount
        );
        IERC20 _pairAddress = kashiPair.asset();
        uint256 LPBought = _performZapIn(
            _FromTokenContractAddress,
            address(_pairAddress),
            toInvest,
            _swapTarget,
            swapData
        );
        require(LPBought >= _minPoolTokens, "ERR: High Slippage");
        emit ZapIn(to, address(_pairAddress), LPBought);
        _pairAddress.safeTransfer(address(bento), LPBought);
        IBentoBridge(bento).deposit(_pairAddress, address(bento), address(kashiPair), LPBought, 0); 
        fraction = kashiPair.addAsset(to, true, LPBought);
    }
/*
██   ██       ▄   ▄███▄   
█ █  █ █       █  █▀   ▀  
█▄▄█ █▄▄█ █     █ ██▄▄    
█  █ █  █  █    █ █▄   ▄▀ 
   █    █   █  █  ▀███▀   
  █    █     █▐           
 ▀    ▀      ▐         */
    
    /***********
    AAVE HELPERS 
    ***********/
    function balanceToAave(address underlying, address to) external {
        aave.deposit(underlying, IERC20(underlying).safeBalanceOfSelf(), to, 0); 
    }

    function balanceFromAave(address aToken, address to) external {
        address underlying = IAaveBridge(aToken).UNDERLYING_ASSET_ADDRESS(); // sanity check for `underlying` token
        aave.withdraw(underlying, IERC20(aToken).safeBalanceOfSelf(), to); 
    }
    
    /**************************
    AAVE -> UNDERLYING -> BENTO 
    **************************/
    /// @notice Migrate AAVE `aToken` underlying `amount` into BENTO for benefit of `to` by batching calls to `aave` and `bento`.
    function aaveToBento(address aToken, address to, uint256 amount) external returns (uint256 amountOut, uint256 shareOut) {
        IERC20(aToken).safeTransferFrom(msg.sender, address(this), amount); // deposit `msg.sender` `aToken` `amount` into this contract
        address underlying = IAaveBridge(aToken).UNDERLYING_ASSET_ADDRESS(); // sanity check for `underlying` token
        aave.withdraw(underlying, amount, address(bento)); // burn deposited `aToken` from `aave` into `underlying`
        (amountOut, shareOut) = bento.deposit(IERC20(underlying), address(bento), to, amount, 0); // stake `underlying` into BENTO for `to`
    }

    /**************************
    BENTO -> UNDERLYING -> AAVE 
    **************************/
    /// @notice Migrate `underlying` `amount` from BENTO into AAVE for benefit of `to` by batching calls to `bento` and `aave`.
    function bentoToAave(IERC20 underlying, address to, uint256 amount) external {
        bento.withdraw(underlying, msg.sender, address(this), amount, 0); // withdraw `amount` of `underlying` from BENTO into this contract
        aave.deposit(address(underlying), amount, to, 0); // stake `underlying` into `aave` for `to`
    }
    
    /*************************
    AAVE -> UNDERLYING -> COMP 
    *************************/
    /// @notice Migrate AAVE `aToken` underlying `amount` into COMP/CREAM `cToken` for benefit of `to` by batching calls to `aave` and `cToken`.
    function aaveToCompound(address aToken, address cToken, address to, uint256 amount) external {
        IERC20(aToken).safeTransferFrom(msg.sender, address(this), amount); // deposit `msg.sender` `aToken` `amount` into this contract
        address underlying = IAaveBridge(aToken).UNDERLYING_ASSET_ADDRESS(); // sanity check for `underlying` token
        aave.withdraw(underlying, amount, address(this)); // burn deposited `aToken` from `aave` into `underlying`
        ICompoundBridge(cToken).mint(amount); // stake `underlying` into `cToken`
        IERC20(cToken).safeTransfer(to, IERC20(cToken).safeBalanceOfSelf()); // transfer resulting `cToken` to `to`
    }
    
    /*************************
    COMP -> UNDERLYING -> AAVE 
    *************************/
    /// @notice Migrate COMP/CREAM `cToken` underlying `amount` into AAVE for benefit of `to` by batching calls to `cToken` and `aave`.
    function compoundToAave(address cToken, address to, uint256 amount) external {
        IERC20(cToken).safeTransferFrom(msg.sender, address(this), amount); // deposit `msg.sender` `cToken` `amount` into this contract
        ICompoundBridge(cToken).redeem(amount); // burn deposited `cToken` into `underlying`
        address underlying = ICompoundBridge(cToken).underlying(); // sanity check for `underlying` token
        aave.deposit(underlying, IERC20(underlying).safeBalanceOfSelf(), to, 0); // stake resulting `underlying` into `aave` for `to`
    }
    
    /**********************
    SUSHI -> XSUSHI -> AAVE 
    **********************/
    /// @notice Stake SUSHI `amount` into aXSUSHI for benefit of `to` by batching calls to `sushiBar` and `aave`.
    function stakeSushiToAave(address to, uint256 amount) external { // SAAVE
        sushiToken.safeTransferFrom(msg.sender, address(this), amount); // deposit `msg.sender` SUSHI `amount` into this contract
        ISushiBarBridge(sushiBar).enter(amount); // stake deposited SUSHI into `sushiBar` xSUSHI
        aave.deposit(sushiBar, IERC20(sushiBar).safeBalanceOfSelf(), to, 0); // stake resulting xSUSHI into `aave` aXSUSHI for `to`
    }
    
    /**********************
    AAVE -> XSUSHI -> SUSHI 
    **********************/
    /// @notice Unstake aXSUSHI `amount` into SUSHI for benefit of `to` by batching calls to `aave` and `sushiBar`.
    function unstakeSushiFromAave(address to, uint256 amount) external {
        aaveSushiToken.safeTransferFrom(msg.sender, address(this), amount); // deposit `msg.sender` aXSUSHI `amount` into this contract
        aave.withdraw(sushiBar, amount, address(this)); // burn deposited aXSUSHI from `aave` into xSUSHI
        ISushiBarBridge(sushiBar).leave(amount); // burn resulting xSUSHI from `sushiBar` into SUSHI
        sushiToken.safeTransfer(to, sushiToken.safeBalanceOfSelf()); // transfer resulting SUSHI to `to`
    }
/*
███   ▄███▄      ▄     ▄▄▄▄▀ ████▄ 
█  █  █▀   ▀      █ ▀▀▀ █    █   █ 
█ ▀ ▄ ██▄▄    ██   █    █    █   █ 
█  ▄▀ █▄   ▄▀ █ █  █   █     ▀████ 
███   ▀███▀   █  █ █  ▀            
              █   ██            */ 
    /************
    BENTO HELPERS 
    ************/
    function balanceToBento(IERC20 token, address to) external returns (uint256 amountOut, uint256 shareOut) {
        (amountOut, shareOut) = bento.deposit(token, address(this), to, token.safeBalanceOfSelf(), 0); 
    }
    
    /// @dev Included to be able to approve `bento` in the same transaction (using `batch()`).
    function setBentoApproval(
        address user,
        address masterContract,
        bool approved,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        bento.setMasterContractApproval(user, masterContract, approved, v, r, s);
    }
    
    /// @notice Liquidity zap into BENTO.
    function zapToBento(
        address to,
        address _FromTokenContractAddress,
        address _pairAddress,
        uint256 _amount,
        uint256 _minPoolTokens,
        address _swapTarget,
        bytes calldata swapData
    ) external payable returns (uint256) {
        uint256 toInvest = _pullTokens(
            _FromTokenContractAddress,
            _amount
        );
        uint256 LPBought = _performZapIn(
            _FromTokenContractAddress,
            _pairAddress,
            toInvest,
            _swapTarget,
            swapData
        );
        require(LPBought >= _minPoolTokens, "ERR: High Slippage");
        emit ZapIn(to, _pairAddress, LPBought);
        bento.deposit(IERC20(_pairAddress), address(this), to, LPBought, 0); 
        return LPBought;
    }

    /// @notice Liquidity unzap from BENTO.
    function zapFromBento(
        address pair,
        address to,
        uint256 amount
    ) external returns (uint256 amount0, uint256 amount1) {
        bento.withdraw(IERC20(pair), msg.sender, pair, amount, 0); // withdraw `amount` to `pair` from BENTO
        (amount0, amount1) = ISushiSwap(pair).burn(to); // trigger burn to redeem liquidity for `to`
    }

    /***********************
    SUSHI -> XSUSHI -> BENTO 
    ***********************/
    /// @notice Stake SUSHI `amount` into BENTO xSUSHI for benefit of `to` by batching calls to `sushiBar` and `bento`.
    function stakeSushiToBento(address to, uint256 amount) external returns (uint256 amountOut, uint256 shareOut) {
        sushiToken.safeTransferFrom(msg.sender, address(this), amount); // deposit `msg.sender` SUSHI `amount` into this contract
        ISushiBarBridge(sushiBar).enter(amount); // stake deposited SUSHI into `sushiBar` xSUSHI
        (amountOut, shareOut) = bento.deposit(IERC20(sushiBar), address(this), to, IERC20(sushiBar).safeBalanceOfSelf(), 0); // stake resulting xSUSHI into BENTO for `to`
    }
    
    /***********************
    BENTO -> XSUSHI -> SUSHI 
    ***********************/
    /// @notice Unstake xSUSHI `amount` from BENTO into SUSHI for benefit of `to` by batching calls to `bento` and `sushiBar`.
    function unstakeSushiFromBento(address to, uint256 amount) external {
        bento.withdraw(IERC20(sushiBar), msg.sender, address(this), amount, 0); // withdraw `amount` of xSUSHI from BENTO into this contract
        ISushiBarBridge(sushiBar).leave(amount); // burn withdrawn xSUSHI from `sushiBar` into SUSHI
        sushiToken.safeTransfer(to, sushiToken.safeBalanceOfSelf()); // transfer resulting SUSHI to `to`
    }
/*    
▄█▄    █▄▄▄▄ ▄███▄   ██   █▀▄▀█ 
█▀ ▀▄  █  ▄▀ █▀   ▀  █ █  █ █ █ 
█   ▀  █▀▀▌  ██▄▄    █▄▄█ █ ▄ █ 
█▄  ▄▀ █  █  █▄   ▄▀ █  █ █   █ 
▀███▀    █   ▀███▀      █    █  
        ▀              █    ▀  
                      ▀      */
// - COMPOUND - //
    /***********
    COMP HELPERS 
    ***********/
    function balanceToCompound(ICompoundBridge cToken) external {
        IERC20 underlying = IERC20(ICompoundBridge(cToken).underlying()); // sanity check for `underlying` token
        cToken.mint(underlying.safeBalanceOfSelf());
    }

    function balanceFromCompound(address cToken) external {
        ICompoundBridge(cToken).redeem(IERC20(cToken).safeBalanceOfSelf());
    }
    
    /**************************
    COMP -> UNDERLYING -> BENTO 
    **************************/
    /// @notice Migrate COMP/CREAM `cToken` `cTokenAmount` into underlying and BENTO for benefit of `to` by batching calls to `cToken` and `bento`.
    function compoundToBento(address cToken, address to, uint256 cTokenAmount) external returns (uint256 amountOut, uint256 shareOut) {
        IERC20(cToken).safeTransferFrom(msg.sender, address(this), cTokenAmount); // deposit `msg.sender` `cToken` `cTokenAmount` into this contract
        ICompoundBridge(cToken).redeem(cTokenAmount); // burn deposited `cToken` into `underlying`
        IERC20 underlying = IERC20(ICompoundBridge(cToken).underlying()); // sanity check for `underlying` token
        (amountOut, shareOut) = bento.deposit(underlying, address(this), to, underlying.safeBalanceOfSelf(), 0); // stake resulting `underlying` into BENTO for `to`
    }
    
    /**************************
    BENTO -> UNDERLYING -> COMP 
    **************************/
    /// @notice Migrate `cToken` `underlyingAmount` from BENTO into COMP/CREAM for benefit of `to` by batching calls to `bento` and `cToken`.
    function bentoToCompound(address cToken, address to, uint256 underlyingAmount) external {
        IERC20 underlying = IERC20(ICompoundBridge(cToken).underlying()); // sanity check for `underlying` token
        bento.withdraw(underlying, msg.sender, address(this), underlyingAmount, 0); // withdraw `underlyingAmount` of `underlying` from BENTO into this contract
        ICompoundBridge(cToken).mint(underlyingAmount); // stake `underlying` into `cToken`
        IERC20(cToken).safeTransfer(to, IERC20(cToken).safeBalanceOfSelf()); // transfer resulting `cToken` to `to`
    }
    
    /**********************
    SUSHI -> CREAM -> BENTO 
    **********************/
    /// @notice Stake SUSHI `amount` into crSUSHI and BENTO for benefit of `to` by batching calls to `crSushiToken` and `bento`.
    function sushiToCreamToBento(address to, uint256 amount) external returns (uint256 amountOut, uint256 shareOut) {
        sushiToken.safeTransferFrom(msg.sender, address(this), amount); // deposit `msg.sender` SUSHI `amount` into this contract
        ICompoundBridge(crSushiToken).mint(amount); // stake deposited SUSHI into crSUSHI
        (amountOut, shareOut) = bento.deposit(IERC20(crSushiToken), address(this), to, IERC20(crSushiToken).safeBalanceOfSelf(), 0); // stake resulting crSUSHI into BENTO for `to`
    }
    
    /**********************
    BENTO -> CREAM -> SUSHI 
    **********************/
    /// @notice Unstake crSUSHI `cTokenAmount` into SUSHI from BENTO for benefit of `to` by batching calls to `bento` and `crSushiToken`.
    function sushiFromCreamFromBento(address to, uint256 cTokenAmount) external {
        bento.withdraw(IERC20(crSushiToken), msg.sender, address(this), cTokenAmount, 0); // withdraw `cTokenAmount` of `crSushiToken` from BENTO into this contract
        ICompoundBridge(crSushiToken).redeem(cTokenAmount); // burn deposited `crSushiToken` into SUSHI
        sushiToken.safeTransfer(to, sushiToken.safeBalanceOfSelf()); // transfer resulting SUSHI to `to`
    }
    
    /***********************
    SUSHI -> XSUSHI -> CREAM 
    ***********************/
    /// @notice Stake SUSHI `amount` into crXSUSHI for benefit of `to` by batching calls to `sushiBar` and `crXSushiToken`.
    function stakeSushiToCream(address to, uint256 amount) external { // SCREAM
        sushiToken.safeTransferFrom(msg.sender, address(this), amount); // deposit `msg.sender` SUSHI `amount` into this contract
        ISushiBarBridge(sushiBar).enter(amount); // stake deposited SUSHI `amount` into `sushiBar` xSUSHI
        ICompoundBridge(crXSushiToken).mint(IERC20(sushiBar).safeBalanceOfSelf()); // stake resulting xSUSHI into crXSUSHI
        IERC20(crXSushiToken).safeTransfer(to, IERC20(crXSushiToken).safeBalanceOfSelf()); // transfer resulting crXSUSHI to `to`
    }
    
    /***********************
    CREAM -> XSUSHI -> SUSHI 
    ***********************/
    /// @notice Unstake crXSUSHI `cTokenAmount` into SUSHI for benefit of `to` by batching calls to `crXSushiToken` and `sushiBar`.
    function unstakeSushiFromCream(address to, uint256 cTokenAmount) external {
        IERC20(crXSushiToken).safeTransferFrom(msg.sender, address(this), cTokenAmount); // deposit `msg.sender` `crXSushiToken` `cTokenAmount` into this contract
        ICompoundBridge(crXSushiToken).redeem(cTokenAmount); // burn deposited `crXSushiToken` `cTokenAmount` into xSUSHI
        ISushiBarBridge(sushiBar).leave(IERC20(sushiBar).safeBalanceOfSelf()); // burn resulting xSUSHI `amount` from `sushiBar` into SUSHI
        sushiToken.safeTransfer(to, sushiToken.safeBalanceOfSelf()); // transfer resulting SUSHI to `to`
    }
    
    /********************************
    SUSHI -> XSUSHI -> CREAM -> BENTO 
    ********************************/
    /// @notice Stake SUSHI `amount` into crXSUSHI and BENTO for benefit of `to` by batching calls to `sushiBar`, `crXSushiToken` and `bento`.
    function stakeSushiToCreamToBento(address to, uint256 amount) external returns (uint256 amountOut, uint256 shareOut) {
        sushiToken.safeTransferFrom(msg.sender, address(this), amount); // deposit `msg.sender` SUSHI `amount` into this contract
        ISushiBarBridge(sushiBar).enter(amount); // stake deposited SUSHI `amount` into `sushiBar` xSUSHI
        ICompoundBridge(crXSushiToken).mint(IERC20(sushiBar).safeBalanceOfSelf()); // stake resulting xSUSHI into crXSUSHI
        (amountOut, shareOut) = bento.deposit(IERC20(crXSushiToken), address(this), to, IERC20(crXSushiToken).safeBalanceOfSelf(), 0); // stake resulting crXSUSHI into BENTO for `to`
    }
    
    /********************************
    BENTO -> CREAM -> XSUSHI -> SUSHI 
    ********************************/
    /// @notice Unstake crXSUSHI `cTokenAmount` into SUSHI from BENTO for benefit of `to` by batching calls to `bento`, `crXSushiToken` and `sushiBar`.
    function unstakeSushiFromCreamFromBento(address to, uint256 cTokenAmount) external {
        bento.withdraw(IERC20(crXSushiToken), msg.sender, address(this), cTokenAmount, 0); // withdraw `cTokenAmount` of `crXSushiToken` from BENTO into this contract
        ICompoundBridge(crXSushiToken).redeem(cTokenAmount); // burn deposited `crXSushiToken` `cTokenAmount` into xSUSHI
        ISushiBarBridge(sushiBar).leave(IERC20(sushiBar).safeBalanceOfSelf()); // burn resulting xSUSHI from `sushiBar` into SUSHI
        sushiToken.safeTransfer(to, sushiToken.safeBalanceOfSelf()); // transfer resulting SUSHI to `to`
    }
/*
   ▄▄▄▄▄    ▄ ▄   ██   █ ▄▄      
  █     ▀▄ █   █  █ █  █   █     
▄  ▀▀▀▀▄  █ ▄   █ █▄▄█ █▀▀▀      
 ▀▄▄▄▄▀   █  █  █ █  █ █         
           █ █ █     █  █        
            ▀ ▀     █    ▀       
                   ▀     */
    /// @notice Fallback for received ETH - SushiSwap ETH to stake SUSHI into xSUSHI and BENTO for benefit of `to`.
    receive() external payable { // INARIZUSHI
        (uint256 reserve0, uint256 reserve1, ) = sushiSwapSushiETHPair.getReserves();
        uint256 amountInWithFee = msg.value.mul(997);
        uint256 out =
            amountInWithFee.mul(reserve0) /
            reserve1.mul(1000).add(amountInWithFee);
        IWETH(wETH).deposit{value: msg.value}();
        IERC20(wETH).safeTransfer(address(sushiSwapSushiETHPair), msg.value);
        sushiSwapSushiETHPair.swap(out, 0, address(this), "");
        ISushiBarBridge(sushiBar).enter(sushiToken.safeBalanceOfSelf()); // stake resulting SUSHI into `sushiBar` xSUSHI
        bento.deposit(IERC20(sushiBar), address(this), msg.sender, IERC20(sushiBar).safeBalanceOfSelf(), 0); // stake resulting xSUSHI into BENTO for `to`
    }
    
    /// @notice SushiSwap ETH to stake SUSHI into xSUSHI and BENTO for benefit of `to`. 
    function inariZushi(address to) external payable returns (uint256 amountOut, uint256 shareOut) {
        (uint256 reserve0, uint256 reserve1, ) = sushiSwapSushiETHPair.getReserves();
        uint256 amountInWithFee = msg.value.mul(997);
        uint256 out =
            amountInWithFee.mul(reserve0) /
            reserve1.mul(1000).add(amountInWithFee);
        IWETH(wETH).deposit{value: msg.value}();
        IERC20(wETH).safeTransfer(address(sushiSwapSushiETHPair), msg.value);
        sushiSwapSushiETHPair.swap(out, 0, address(this), "");
        ISushiBarBridge(sushiBar).enter(sushiToken.safeBalanceOfSelf()); // stake resulting SUSHI into `sushiBar` xSUSHI
        (amountOut, shareOut) = bento.deposit(IERC20(sushiBar), address(this), to, IERC20(sushiBar).safeBalanceOfSelf(), 0); // stake resulting xSUSHI into BENTO for `to`
    }
    
    /// @notice Simple SushiSwap `fromToken` `amountIn` to `toToken` for benefit of `to`.
    function swap(address fromToken, address toToken, address to, uint256 amountIn) external returns (uint256 amountOut) {
        (address token0, address token1) = fromToken < toToken ? (fromToken, toToken) : (toToken, fromToken);
        ISushiSwap pair =
            ISushiSwap(
                uint256(
                    keccak256(abi.encodePacked(hex"ff", sushiSwapFactory, keccak256(abi.encodePacked(token0, token1)), pairCodeHash))
                )
            );
        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
        uint256 amountInWithFee = amountIn.mul(997);
        IERC20(fromToken).safeTransferFrom(msg.sender, address(pair), amountIn);
        if (toToken > fromToken) {
            amountOut =
                amountInWithFee.mul(reserve1) /
                reserve0.mul(1000).add(amountInWithFee);
            pair.swap(0, amountOut, to, "");
        } else {
            amountOut =
                amountInWithFee.mul(reserve0) /
                reserve1.mul(1000).add(amountInWithFee);
            pair.swap(amountOut, 0, to, "");
        }
    }

    /// @notice Simple SushiSwap local `fromToken` balance in this contract to `toToken` for benefit of `to`.
    function swapBalance(address fromToken, address toToken, address to) external returns (uint256 amountOut) {
        (address token0, address token1) = fromToken < toToken ? (fromToken, toToken) : (toToken, fromToken);
        ISushiSwap pair =
            ISushiSwap(
                uint256(
                    keccak256(abi.encodePacked(hex"ff", sushiSwapFactory, keccak256(abi.encodePacked(token0, token1)), pairCodeHash))
                )
            );
        uint256 amountIn = IERC20(fromToken).safeBalanceOfSelf();
        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
        uint256 amountInWithFee = amountIn.mul(997);
        IERC20(fromToken).safeTransfer(address(pair), amountIn);
        if (toToken > fromToken) {
            amountOut =
                amountInWithFee.mul(reserve1) /
                reserve0.mul(1000).add(amountInWithFee);
            pair.swap(0, amountOut, to, "");
        } else {
            amountOut =
                amountInWithFee.mul(reserve0) /
                reserve1.mul(1000).add(amountInWithFee);
            pair.swap(amountOut, 0, to, "");
        }
    }
}
