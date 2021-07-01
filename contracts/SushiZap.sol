// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import "./libraries/BoringERC20.sol";
import "./libraries/SafeMath.sol";

/// @notice SushiSwap liquidity zaps based on awesomeness from zapper.fi (0xcff6eF0B9916682B37D80c19cFF8949bc1886bC2).
contract SushiZap {
    using SafeMath for uint256;
    using BoringERC20 for IERC20;
    
    address constant sushiSwapFactory = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac; // SushiSwap factory contract
    ISushiSwap constant sushiSwapRouter = ISushiSwap(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F); // SushiSwap router contract
    uint256 constant deadline = 0xf000000000000000000000000000000000000000000000000000000000000000; // placeholder for swap deadline
    bytes32 constant pairCodeHash = 0xe18a34eb0e04b04f7a0ac29a6e80748dca96319b42c54d679cb821dca90c6303; // SushiSwap pair code hash

    event ZapIn(address sender, address pool, uint256 tokensRec);

    /**
     @notice This function is used to invest in given SushiSwap pair through ETH/ERC20 Tokens.
     @param to Address to receive LP tokens.
     @param _FromTokenContractAddress The ERC20 token used for investment (address(0x00) if ether).
     @param _pairAddress The SushiSwap pair address.
     @param _amount The amount of fromToken to invest.
     @param _minPoolTokens Reverts if less tokens received than this.
     @param _swapTarget Excecution target for the first swap.
     @param swapData Dex quote data.
     @return Amount of LP bought.
     */
    function zapIn(
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
        require(LPBought >= _minPoolTokens, 'ERR: High Slippage');
        emit ZapIn(to, _pairAddress, LPBought);
        IERC20(_pairAddress).safeTransfer(to, LPBought);
        return LPBought;
    }

    function _getPairTokens(address _pairAddress) private pure returns (address token0, address token1)
    {
        ISushiSwap sushiPair = ISushiSwap(_pairAddress);
        token0 = sushiPair.token0();
        token1 = sushiPair.token1();
    }

    function _pullTokens(address token, uint256 amount) internal returns (uint256 value) {
        if (token == address(0)) {
            require(msg.value > 0, 'No eth sent');
            return msg.value;
        }
        require(amount > 0, 'Invalid token amount');
        require(msg.value == 0, 'Eth sent with token');
        // transfer token
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        return amount;
    }

    function _performZapIn(
        address _FromTokenContractAddress,
        address _pairAddress,
        uint256 _amount,
        address _swapTarget,
        bytes memory swapData
    ) internal returns (uint256) {
        uint256 intermediateAmt;
        address intermediateToken;
        (
            address _ToSushipoolToken0,
            address _ToSushipoolToken1
        ) = _getPairTokens(_pairAddress);
        if (
            _FromTokenContractAddress != _ToSushipoolToken0 &&
            _FromTokenContractAddress != _ToSushipoolToken1
        ) {
            // swap to intermediate
            (intermediateAmt, intermediateToken) = _fillQuote(
                _FromTokenContractAddress,
                _pairAddress,
                _amount,
                _swapTarget,
                swapData
            );
        } else {
            intermediateToken = _FromTokenContractAddress;
            intermediateAmt = _amount;
        }
        // divide intermediate into appropriate amount to add liquidity
        (uint256 token0Bought, uint256 token1Bought) = _swapIntermediate(
            intermediateToken,
            _ToSushipoolToken0,
            _ToSushipoolToken1,
            intermediateAmt
        );
        return
            _sushiDeposit(
                _ToSushipoolToken0,
                _ToSushipoolToken1,
                token0Bought,
                token1Bought
            );
    }

    function _sushiDeposit(
        address _ToUnipoolToken0,
        address _ToUnipoolToken1,
        uint256 token0Bought,
        uint256 token1Bought
    ) private returns (uint256) {
        IERC20(_ToUnipoolToken0).safeApprove(address(sushiSwapRouter), 0);
        IERC20(_ToUnipoolToken1).safeApprove(address(sushiSwapRouter), 0);
        IERC20(_ToUnipoolToken0).safeApprove(
            address(sushiSwapRouter),
            token0Bought
        );
        IERC20(_ToUnipoolToken1).safeApprove(
            address(sushiSwapRouter),
            token1Bought
        );
        (uint256 amountA, uint256 amountB, uint256 LP) = sushiSwapRouter
            .addLiquidity(
            _ToUnipoolToken0,
            _ToUnipoolToken1,
            token0Bought,
            token1Bought,
            1,
            1,
            address(this),
            deadline
        );
            // returning residue in token0, if any
            if (token0Bought.sub(amountA) > 0) {
                IERC20(_ToUnipoolToken0).safeTransfer(
                    msg.sender,
                    token0Bought.sub(amountA)
                );
            }
            // returning residue in token1, if any
            if (token1Bought.sub(amountB) > 0) {
                IERC20(_ToUnipoolToken1).safeTransfer(
                    msg.sender,
                    token1Bought.sub(amountB)
                );
            }
        return LP;
    }

    function _fillQuote(
        address _fromTokenAddress,
        address _pairAddress,
        uint256 _amount,
        address _swapTarget,
        bytes memory swapCallData
    ) private returns (uint256 amountBought, address intermediateToken) {
        uint256 valueToSend;
        if (_fromTokenAddress == address(0)) {
            valueToSend = _amount;
        } else {
            IERC20 fromToken = IERC20(_fromTokenAddress);
            fromToken.safeApprove(address(_swapTarget), 0);
            fromToken.safeApprove(address(_swapTarget), _amount);
        }
        (address _token0, address _token1) = _getPairTokens(_pairAddress);
        IERC20 token0 = IERC20(_token0);
        IERC20 token1 = IERC20(_token1);
        uint256 initialBalance0 = token0.safeBalanceOfSelf();
        uint256 initialBalance1 = token1.safeBalanceOfSelf();
        (bool success, ) = _swapTarget.call{value: valueToSend}(swapCallData);
        require(success, 'Error Swapping Tokens 1');
        uint256 finalBalance0 = token0.safeBalanceOfSelf().sub(
            initialBalance0
        );
        uint256 finalBalance1 = token1.safeBalanceOfSelf().sub(
            initialBalance1
        );
        if (finalBalance0 > finalBalance1) {
            amountBought = finalBalance0;
            intermediateToken = _token0;
        } else {
            amountBought = finalBalance1;
            intermediateToken = _token1;
        }
        require(amountBought > 0, 'Swapped to Invalid Intermediate');
    }

    function _swapIntermediate(
        address _toContractAddress,
        address _ToSushipoolToken0,
        address _ToSushipoolToken1,
        uint256 _amount
    ) private returns (uint256 token0Bought, uint256 token1Bought) {
        (address token0, address token1) = _ToSushipoolToken0 < _ToSushipoolToken1 ? (_ToSushipoolToken0, _ToSushipoolToken1) : (_ToSushipoolToken1, _ToSushipoolToken0);
        ISushiSwap pair =
            ISushiSwap(
                uint256(
                    keccak256(abi.encodePacked(hex"ff", sushiSwapFactory, keccak256(abi.encodePacked(token0, token1)), pairCodeHash))
                )
            );
        (uint256 res0, uint256 res1, ) = pair.getReserves();
        if (_toContractAddress == _ToSushipoolToken0) {
            uint256 amountToSwap = calculateSwapInAmount(res0, _amount);
            // if no reserve or a new pair is created
            if (amountToSwap <= 0) amountToSwap = _amount / 2;
            token1Bought = _token2Token(
                _toContractAddress,
                _ToSushipoolToken1,
                amountToSwap
            );
            token0Bought = _amount.sub(amountToSwap);
        } else {
            uint256 amountToSwap = calculateSwapInAmount(res1, _amount);
            // if no reserve or a new pair is created
            if (amountToSwap <= 0) amountToSwap = _amount / 2;
            token0Bought = _token2Token(
                _toContractAddress,
                _ToSushipoolToken0,
                amountToSwap
            );
            token1Bought = _amount.sub(amountToSwap);
        }
    }

    function calculateSwapInAmount(uint256 reserveIn, uint256 userIn) private pure returns (uint256)
    {
        return
            Babylonian
                .sqrt(
                reserveIn.mul(userIn.mul(3988000) + reserveIn.mul(3988009))
            )
                .sub(reserveIn.mul(1997)) / 1994;
    }

    /**
     @notice This function is used to swap ERC20 <> ERC20.
     @param _FromTokenContractAddress The token address to swap from.
     @param _ToTokenContractAddress The token address to swap to. 
     @param tokens2Trade The amount of tokens to swap.
     @return tokenBought The quantity of tokens bought.
    */
    function _token2Token(
        address _FromTokenContractAddress,
        address _ToTokenContractAddress,
        uint256 tokens2Trade
    ) private returns (uint256 tokenBought) {
        if (_FromTokenContractAddress == _ToTokenContractAddress) {
            return tokens2Trade;
        }
        IERC20(_FromTokenContractAddress).safeApprove(
            address(sushiSwapRouter),
            0
        );
        IERC20(_FromTokenContractAddress).safeApprove(
            address(sushiSwapRouter),
            tokens2Trade
        );
        (address token0, address token1) = _FromTokenContractAddress < _ToTokenContractAddress ? (_FromTokenContractAddress, _ToTokenContractAddress) : (_ToTokenContractAddress, _FromTokenContractAddress);
        address pair =
            address(
                uint256(
                    keccak256(abi.encodePacked(hex"ff", sushiSwapFactory, keccak256(abi.encodePacked(token0, token1)), pairCodeHash))
                )
            );
        require(pair != address(0), 'No Swap Available');
        address[] memory path = new address[](2);
        path[0] = _FromTokenContractAddress;
        path[1] = _ToTokenContractAddress;
        tokenBought = sushiSwapRouter.swapExactTokensForTokens(
            tokens2Trade,
            1,
            path,
            address(this),
            deadline
        )[path.length - 1];
        require(tokenBought > 0, 'Error Swapping Tokens 2');
    }
    
    function zapOut(
        address pair,
        address to,
        uint256 amount
    ) external returns (uint256 amount0, uint256 amount1) {
        IERC20(pair).safeTransferFrom(msg.sender, pair, amount); // pull `amount` to `pair`
        (amount0, amount1) = ISushiSwap(pair).burn(to); // trigger burn to redeem liquidity for `to`
    }
    
    function zapOutBalance(
        address pair,
        address to
    ) external returns (uint256 amount0, uint256 amount1) {
        IERC20(pair).safeTransfer(pair, IERC20(pair).safeBalanceOfSelf()); // transfer local balance to `pair`
        (amount0, amount1) = ISushiSwap(pair).burn(to); // trigger burn to redeem liquidity for `to`
    }
}
