// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SafeTransferLib} from "./utils/SafeTransferLib.sol";
import {LaunchToken} from "./LaunchToken.sol";
import {DEXFactory} from "./DEXFactory.sol";
import {IWrappedNative} from "./interfaces/IWrappedNative.sol";
import {LaunchpadFactory} from "./LaunchpadFactory.sol";

interface IDEXPairMinimal {
    function mint(address to) external returns (uint256 liquidity);
}

/// @title BondingCurve
/// @notice Handles primary-market trading until graduation into the Pod.fun DEX.
contract BondingCurve {
    using SafeTransferLib for address;

    uint256 private constant BPS = 10_000;

    LaunchToken public immutable token;
    LaunchpadFactory public immutable factory;
    DEXFactory public immutable dexFactory;
    IWrappedNative public immutable wrappedNative;
    uint256 public immutable launchId;

    address public feeRecipient;
    uint256 public buyFeeBps;
    uint256 public sellFeeBps;
    uint256 public launchFeeBps;
    uint256 public graduationThreshold;

    uint256 public reserveToken;
    uint256 public reservePEth;

    bool public initialized;
    bool public graduated;

    event Initialized(address indexed creator, uint256 pEthLiquidity, uint256 tokenLiquidity);
    event Buy(address indexed buyer, address indexed to, uint256 amountIn, uint256 tokensOut, uint256 fee);
    event Sell(address indexed seller, address indexed to, uint256 amountIn, uint256 pEthOut, uint256 fee);
    event Graduated(address indexed dexPair, uint256 remainingToken, uint256 remainingPEth);

    error OnlyFactory();
    error TradingClosed();
    error AlreadyInitialized();
    error AlreadyGraduated();
    error GraduationThresholdNotMet();

    constructor(
        LaunchToken token_,
        LaunchpadFactory factory_,
        DEXFactory dexFactory_,
        IWrappedNative wrappedNative_,
        address feeRecipient_,
        uint256 launchFeeBps_,
        uint256 buyFeeBps_,
        uint256 sellFeeBps_,
        uint256 graduationThreshold_,
        uint256 launchId_
    ) {
        token = token_;
        factory = factory_;
        dexFactory = dexFactory_;
        wrappedNative = wrappedNative_;
        feeRecipient = feeRecipient_;
        launchFeeBps = launchFeeBps_;
        buyFeeBps = buyFeeBps_;
        sellFeeBps = sellFeeBps_;
        graduationThreshold = graduationThreshold_;
        launchId = launchId_;
    }

    modifier onlyFactory() {
        if (msg.sender != address(factory)) revert OnlyFactory();
        _;
    }

    modifier ensureTrading() {
        if (!initialized || graduated) revert TradingClosed();
        _;
    }

    function initialize(address creator) external payable onlyFactory {
        if (initialized) revert AlreadyInitialized();
        initialized = true;

        uint256 totalTokens = token.balanceOf(address(this));
        require(totalTokens > 0, "TokensMissing");
        uint256 launchFee = msg.value * launchFeeBps / BPS;
        if (launchFee > 0) SafeTransferLib.safeTransferETH(feeRecipient, launchFee);
        reservePEth = msg.value - launchFee;
        reserveToken = totalTokens;
        emit Initialized(creator, reservePEth, totalTokens);
    }

    function buy(uint256 minTokensOut, address to) external payable ensureTrading returns (uint256 tokensOut) {
        require(to != address(0), "ZeroTo");
        uint256 fee = msg.value * buyFeeBps / BPS;
        if (fee > 0) SafeTransferLib.safeTransferETH(feeRecipient, fee);
        uint256 amountIn = msg.value - fee;
        tokensOut = _getAmountOut(amountIn, reservePEth, reserveToken);
        require(tokensOut >= minTokensOut, "Slippage");
        reservePEth += amountIn;
        reserveToken -= tokensOut;
        address(token).safeTransfer(to, tokensOut);
        emit Buy(msg.sender, to, amountIn, tokensOut, fee);
        if (reservePEth >= graduationThreshold) {
            _graduate();
        }
    }

    function sell(uint256 amountIn, uint256 minPEthOut, address payable to)
        external
        ensureTrading
        returns (uint256 pEthOut)
    {
        require(to != address(0), "ZeroTo");
        address(token).safeTransferFrom(msg.sender, address(this), amountIn);
        pEthOut = _getAmountOut(amountIn, reserveToken, reservePEth);
        require(pEthOut >= minPEthOut, "Slippage");
        uint256 fee = pEthOut * sellFeeBps / BPS;
        reserveToken += amountIn;
        reservePEth -= pEthOut;
        if (fee > 0) SafeTransferLib.safeTransferETH(feeRecipient, fee);
        SafeTransferLib.safeTransferETH(to, pEthOut - fee);
        emit Sell(msg.sender, to, amountIn, pEthOut, fee);
    }

    function manualGraduate() external ensureTrading {
        if (reservePEth < graduationThreshold) revert GraduationThresholdNotMet();
        _graduate();
    }

    function _graduate() internal {
        if (graduated) revert AlreadyGraduated();
        graduated = true;
        address pair = dexFactory.createPair(address(token));

        token.enableTrading();
        uint256 tokenBalance = token.balanceOf(address(this));
        uint256 pEthBalance = address(this).balance;
        if (pEthBalance > 0) {
            wrappedNative.deposit{value: pEthBalance}();
        }
        if (tokenBalance > 0) {
            address(token).safeTransfer(pair, tokenBalance);
        }
        if (pEthBalance > 0) {
            address(wrappedNative).safeTransfer(pair, pEthBalance);
        }

        IDEXPairMinimal(pair).mint(address(0));
        factory.notifyGraduation(launchId);
        emit Graduated(pair, tokenBalance, pEthBalance);
        if (address(this).balance > 0) {
            SafeTransferLib.safeTransferETH(feeRecipient, address(this).balance);
        }
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        require(amountIn > 0, "AmountZero");
        require(reserveIn > 0 && reserveOut > 0, "NoLiquidity");
        return amountIn * reserveOut / (reserveIn + amountIn);
    }
}
