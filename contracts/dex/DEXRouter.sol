// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {SafeTransferLib} from "../libraries/SafeTransferLib.sol";
import {IDEXFactory} from "../interfaces/IDEXFactory.sol";
import {IDEXPair} from "../interfaces/IDEXPair.sol";

/// @title DEXRouter
/// @notice Routing layer for interacting with token/pETH pairs.
contract DEXRouter {

    IDEXFactory public immutable factory;

    error Expired();
    error PairUnavailable();

    constructor(address factory_) {
        require(factory_ != address(0), "INVALID_FACTORY");
        factory = IDEXFactory(factory_);
    }

    receive() external payable {}

    function addLiquidity(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountPEthMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountPEth, uint256 liquidity) {
        _ensure(deadline);
        address pair = factory.getPair(token);
        if (pair == address(0)) revert PairUnavailable();
        amountToken = amountTokenDesired;
        amountPEth = msg.value;
        require(amountToken >= amountTokenMin && amountPEth >= amountPEthMin, "SLIPPAGE");
        SafeTransferLib.safeTransferFrom(token, msg.sender, pair, amountToken);
        SafeTransferLib.safeTransferNative(pair, amountPEth);
        liquidity = IDEXPair(pair).mint(to);
    }

    function removeLiquidity(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountPEthMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountToken, uint256 amountPEth) {
        _ensure(deadline);
        address pair = factory.getPair(token);
        if (pair == address(0)) revert PairUnavailable();
        SafeTransferLib.safeTransferFrom(pair, msg.sender, pair, liquidity);
        (amountToken, amountPEth) = IDEXPair(pair).burn(to);
        require(amountToken >= amountTokenMin && amountPEth >= amountPEthMin, "SLIPPAGE");
    }

    function swapExactTokensForPEth(
        address token,
        uint256 amountIn,
        uint256 amountOutMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountOut) {
        _ensure(deadline);
        address pair = factory.getPair(token);
        if (pair == address(0)) revert PairUnavailable();
        (uint256 reserveToken, uint256 reservePEth) = _getReserves(pair);
        amountOut = _getAmountOut(amountIn, reserveToken, reservePEth);
        require(amountOut >= amountOutMin, "SLIPPAGE");
        SafeTransferLib.safeTransferFrom(token, msg.sender, pair, amountIn);
        IDEXPair(pair).swap(to, false, amountOut, msg.sender);
    }

    function swapExactPEthForTokens(
        address token,
        uint256 amountOutMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountOut) {
        _ensure(deadline);
        address pair = factory.getPair(token);
        if (pair == address(0)) revert PairUnavailable();
        (uint256 reserveToken, uint256 reservePEth) = _getReserves(pair);
        amountOut = _getAmountOut(msg.value, reservePEth, reserveToken);
        require(amountOut >= amountOutMin, "SLIPPAGE");
        SafeTransferLib.safeTransferNative(pair, msg.value);
        IDEXPair(pair).swap(to, true, amountOut, msg.sender);
    }

    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) external pure returns (uint256) {
        require(amountA > 0, "INSUFFICIENT_AMOUNT");
        require(reserveA > 0 && reserveB > 0, "INSUFFICIENT_LIQUIDITY");
        return (amountA * reserveB) / reserveA;
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        require(amountIn > 0, "INSUFFICIENT_INPUT");
        require(reserveIn > 0 && reserveOut > 0, "INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;
        return numerator / denominator;
    }

    function _getReserves(address pair) internal view returns (uint256 reserveToken, uint256 reservePEth) {
        reserveToken = IDEXPair(pair).reserveToken();
        reservePEth = IDEXPair(pair).reservePEth();
    }

    function _ensure(uint256 deadline) internal view {
        if (deadline < block.timestamp) revert Expired();
    }
}
