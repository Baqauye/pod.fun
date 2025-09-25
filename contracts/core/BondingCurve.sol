// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ReentrancyGuard} from "../libraries/ReentrancyGuard.sol";
import {SafeTransferLib} from "../libraries/SafeTransferLib.sol";
import {MathLib} from "../libraries/MathLib.sol";
import {ILaunchToken} from "../interfaces/ILaunchToken.sol";
import {IDEXFactory} from "../interfaces/IDEXFactory.sol";
import {IDEXPair} from "../interfaces/IDEXPair.sol";
import {ILaunchpadFactory} from "../interfaces/ILaunchpadFactory.sol";

/// @title BondingCurve
/// @notice Linear bonding curve controlling launch phase liquidity.
contract BondingCurve is ReentrancyGuard {
    uint256 public constant BUY_FEE_BPS = 500; // 5%
    uint256 public constant SELL_FEE_BPS = 100; // 1%
    uint256 public constant WAD = 1e18;

    address public immutable factory;
    address public immutable token;
    address public immutable dexFactory;
    address public immutable router;
    address public immutable treasury;

    uint256 public immutable targetMarketCap;
    uint256 public immutable initialPrice;
    uint256 public immutable slope;

    uint256 public soldTokens;
    uint256 public reservePEth;
    bool public graduated;

    event Purchase(address indexed buyer, address indexed recipient, uint256 tokensOut, uint256 cost, uint256 fee);
    event Sale(address indexed seller, address indexed recipient, uint256 tokensIn, uint256 proceeds, uint256 fee);
    event Graduated(address indexed executor, address pair, uint256 pEthAdded, uint256 tokensAdded);

    error Unauthorized();
    error InvalidState();

    constructor(
        address factory_,
        address token_,
        address dexFactory_,
        address router_,
        address treasury_,
        uint256 targetMarketCap_,
        uint256 initialPrice_,
        uint256 slope_
    ) {
        require(factory_ != address(0) && token_ != address(0), "INVALID_ADDRESS");
        require(dexFactory_ != address(0) && router_ != address(0) && treasury_ != address(0), "INVALID_ADDRESS");
        require(targetMarketCap_ > 0 && initialPrice_ > 0, "INVALID_PARAMS");
        factory = factory_;
        token = token_;
        dexFactory = dexFactory_;
        router = router_;
        treasury = treasury_;
        targetMarketCap = targetMarketCap_;
        initialPrice = initialPrice_;
        slope = slope_;
    }

    modifier onlyFactory() {
        if (msg.sender != factory) revert Unauthorized();
        _;
    }

    function buy(uint256 tokenAmountOut, uint256 maxPayment, address recipient)
        external
        payable
        nonReentrant
        returns (uint256 cost, uint256 fee)
    {
        require(!graduated, "GRADUATED");
        require(tokenAmountOut > 0, "INVALID_AMOUNT");
        cost = _costToBuy(tokenAmountOut);
        fee = (cost * BUY_FEE_BPS) / 10_000;
        uint256 total = cost + fee;
        require(total <= msg.value && total <= maxPayment, "INSUFFICIENT_PAYMENT");
        soldTokens += tokenAmountOut;
        reservePEth += cost;
        SafeTransferLib.safeTransferNative(treasury, fee);
        ILaunchToken(token).transfer(recipient, tokenAmountOut);
        if (msg.value > total) {
            SafeTransferLib.safeTransferNative(msg.sender, msg.value - total);
        }
        emit Purchase(msg.sender, recipient, tokenAmountOut, cost, fee);
        _maybeGraduate();
    }

    function sell(uint256 tokenAmountIn, uint256 minPayout, address recipient)
        external
        nonReentrant
        returns (uint256 proceeds, uint256 fee)
    {
        require(!graduated, "GRADUATED");
        require(tokenAmountIn > 0, "INVALID_AMOUNT");
        require(soldTokens >= tokenAmountIn, "INSUFFICIENT_CIRCULATION");
        proceeds = _proceedsFromSell(tokenAmountIn);
        fee = (proceeds * SELL_FEE_BPS) / 10_000;
        uint256 net = proceeds - fee;
        require(net >= minPayout, "SLIPPAGE");
        soldTokens -= tokenAmountIn;
        reservePEth -= proceeds;
        SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), tokenAmountIn);
        SafeTransferLib.safeTransferNative(recipient, net);
        SafeTransferLib.safeTransferNative(treasury, fee);
        emit Sale(msg.sender, recipient, tokenAmountIn, net, fee);
    }

    function graduate() external nonReentrant {
        _graduate();
    }

    function isGraduated() external view returns (bool) {
        return graduated;
    }

    function spotPrice() public view returns (uint256) {
        return initialPrice + MathLib.mulDiv(slope, soldTokens, WAD);
    }

    function marketCap() public view returns (uint256) {
        return MathLib.mulDiv(spotPrice(), soldTokens, WAD);
    }

    function _maybeGraduate() internal {
        if (!graduated && marketCap() >= targetMarketCap) {
            _graduate();
        }
    }

    function _graduate() internal {
        if (graduated) revert InvalidState();
        graduated = true;
        address pair = IDEXFactory(dexFactory).getPair(token);
        if (pair == address(0)) {
            pair = IDEXFactory(dexFactory).createPair(token);
        }
        uint256 tokenBalance = ILaunchToken(token).balanceOf(address(this));
        uint256 pEthBalance = reservePEth;
        reservePEth = 0;
        SafeTransferLib.safeTransfer(token, pair, tokenBalance);
        SafeTransferLib.safeTransferNative(pair, pEthBalance);
        uint256 liquidity = IDEXPair(pair).mint(address(this));
        IDEXPair(pair).lockLiquidity(liquidity);
        ILaunchToken(token).enableTrading(pair);
        ILaunchpadFactory(factory).notifyGraduation(token);
        emit Graduated(msg.sender, pair, pEthBalance, tokenBalance);
    }

    function _costToBuy(uint256 amount) internal view returns (uint256) {
        uint256 s0 = soldTokens;
        uint256 delta = amount;
        uint256 linear = MathLib.mulDiv(initialPrice, delta, WAD);
        uint256 quad = MathLib.mulDiv(MathLib.mulDiv(slope, delta, 2 * WAD), (2 * s0 + delta), WAD);
        return linear + quad;
    }

    function _proceedsFromSell(uint256 amount) internal view returns (uint256) {
        uint256 s1 = soldTokens;
        uint256 delta = amount;
        uint256 s0 = s1 - delta;
        uint256 linear = MathLib.mulDiv(initialPrice, delta, WAD);
        uint256 quad = MathLib.mulDiv(MathLib.mulDiv(slope, delta, 2 * WAD), (2 * s0 + delta), WAD);
        return linear + quad;
    }

    receive() external payable {}
}
