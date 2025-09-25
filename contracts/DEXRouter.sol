// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SafeTransferLib} from "./utils/SafeTransferLib.sol";
import {IWrappedNative} from "./interfaces/IWrappedNative.sol";
import {DEXFactory} from "./DEXFactory.sol";

interface IDEXPair {
    function factory() external view returns (address);
    function token() external view returns (address);
    function wrappedNative() external view returns (address);
    function getReserves() external view returns (uint112, uint112, uint32);
    function mint(address to) external returns (uint256 liquidity);
    function burn(address to) external returns (uint256 tokenAmount, uint256 wrappedAmount);
    function swap(uint256 amountTokenOut, uint256 amountWrappedOut, address to) external;
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
}

/// @title DEXRouter
/// @notice Routing contract for the Pod.fun DEX with slippage and deadline protections.
contract DEXRouter {
    using SafeTransferLib for address;

    DEXFactory public immutable factory;
    IWrappedNative public immutable wrappedNative;

    event LiquidityAdded(address indexed provider, address indexed token, uint256 tokenAmount, uint256 pEthAmount);
    event LiquidityRemoved(address indexed provider, address indexed token, uint256 tokenAmount, uint256 pEthAmount);
    event SwapExactTokens(address indexed trader, address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);

    constructor(DEXFactory factory_, IWrappedNative wrappedNative_) {
        factory = factory_;
        wrappedNative = wrappedNative_;
    }

    receive() external payable {
        require(msg.sender == address(wrappedNative), "OnlyWrapped");
    }

    function addLiquidityNative(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountNativeMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountNative, uint256 liquidity) {
        _ensureDeadline(deadline);
        address pair = _pairFor(token);

        (amountToken, amountNative) = _optimalLiquidity(pair, token, amountTokenDesired, msg.value, amountTokenMin, amountNativeMin);

        token.safeTransferFrom(msg.sender, pair, amountToken);
        wrappedNative.deposit{value: amountNative}();
        address(wrappedNative).safeTransfer(pair, amountNative);

        liquidity = IDEXPair(pair).mint(to);
        if (msg.value > amountNative) SafeTransferLib.safeTransferETH(msg.sender, msg.value - amountNative);
        emit LiquidityAdded(msg.sender, token, amountToken, amountNative);
    }

    function removeLiquidityNative(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountNativeMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountToken, uint256 amountNative) {
        _ensureDeadline(deadline);
        address pair = _pairFor(token);
        IDEXPair(pair).transferFrom(msg.sender, pair, liquidity);
        (amountToken, amountNative) = IDEXPair(pair).burn(address(this));
        require(amountToken >= amountTokenMin && amountNative >= amountNativeMin, "Slippage");

        token.safeTransfer(to, amountToken);
        wrappedNative.withdraw(amountNative);
        SafeTransferLib.safeTransferETH(to, amountNative);
        emit LiquidityRemoved(msg.sender, token, amountToken, amountNative);
    }

    function swapExactNativeForTokens(
        address tokenOut,
        uint256 amountOutMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountOut) {
        _ensureDeadline(deadline);
        address pair = _pairFor(tokenOut);
        (uint112 reserveToken, uint112 reserveWrapped, ) = IDEXPair(pair).getReserves();
        require(reserveToken > 0 && reserveWrapped > 0, "NoLiquidity");

        uint256 amountIn = msg.value;
        uint256 amountInWithFee = amountIn * 997 / 1000;
        amountOut = amountInWithFee * reserveToken / (reserveWrapped + amountInWithFee);
        require(amountOut >= amountOutMin, "Slippage");

        wrappedNative.deposit{value: amountIn}();
        address(wrappedNative).safeTransfer(pair, amountIn);
        IDEXPair(pair).swap(amountOut, 0, to);
        emit SwapExactTokens(msg.sender, address(0), tokenOut, amountIn, amountOut);
    }

    function swapExactTokensForNative(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountOut) {
        _ensureDeadline(deadline);
        address pair = _pairFor(tokenIn);
        (uint112 reserveToken, uint112 reserveWrapped, ) = IDEXPair(pair).getReserves();
        require(reserveToken > 0 && reserveWrapped > 0, "NoLiquidity");

        uint256 amountInWithFee = amountIn * 997 / 1000;
        amountOut = amountInWithFee * reserveWrapped / (reserveToken + amountInWithFee);
        require(amountOut >= amountOutMin, "Slippage");

        tokenIn.safeTransferFrom(msg.sender, pair, amountIn);
        IDEXPair(pair).swap(0, amountOut, address(this));
        wrappedNative.withdraw(amountOut);
        SafeTransferLib.safeTransferETH(to, amountOut);
        emit SwapExactTokens(msg.sender, tokenIn, address(0), amountIn, amountOut);
    }

    function _pairFor(address token) internal returns (address pair) {
        pair = factory.getPair(token);
        if (pair == address(0)) {
            pair = factory.createPair(token);
        }
    }

    function _optimalLiquidity(
        address pair,
        address token,
        uint256 amountTokenDesired,
        uint256 amountNativeDesired,
        uint256 amountTokenMin,
        uint256 amountNativeMin
    ) internal view returns (uint256 amountToken, uint256 amountNative) {
        if (pair == address(0)) {
            return (amountTokenDesired, amountNativeDesired);
        }
        (uint112 reserveToken, uint112 reserveWrapped, ) = IDEXPair(pair).getReserves();
        if (reserveToken == 0 && reserveWrapped == 0) {
            return (amountTokenDesired, amountNativeDesired);
        }
        uint256 amountNativeOptimal = amountTokenDesired * reserveWrapped / reserveToken;
        if (amountNativeOptimal <= amountNativeDesired) {
            require(amountNativeOptimal >= amountNativeMin, "NativeMin");
            return (amountTokenDesired, amountNativeOptimal);
        } else {
            uint256 amountTokenOptimal = amountNativeDesired * reserveToken / reserveWrapped;
            require(amountTokenOptimal >= amountTokenMin, "TokenMin");
            return (amountTokenOptimal, amountNativeDesired);
        }
    }

    function _ensureDeadline(uint256 deadline) internal view {
        require(deadline >= block.timestamp, "Deadline");
    }
}
