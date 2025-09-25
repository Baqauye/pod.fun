// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SafeTransferLib} from "./utils/SafeTransferLib.sol";
import {Ownable2Step} from "./utils/Ownable.sol";

interface IERC20Minimal {
    function balanceOf(address) external view returns (uint256);

    function transfer(address to, uint256 value) external returns (bool);

    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

/// @title DEXPair
/// @notice Uniswap V2 style constant-product AMM with a focus on on-chain price safety.
contract DEXPair {
    using SafeTransferLib for address;

    uint256 private constant MINIMUM_LIQUIDITY = 1e3;
    uint256 private constant FEE_DENOMINATOR = 1000;
    uint256 private constant SWAP_FEE = 3; // 0.3%

    address public immutable factory;
    address public immutable token;
    address public immutable wrappedNative;

    uint112 private reserveToken;
    uint112 private reserveWrapped;
    uint32 private blockTimestampLast;

    uint256 public priceTokenCumulativeLast;
    uint256 public priceWrappedCumulativeLast;
    uint256 public kLast;

    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;

    event Mint(address indexed sender, uint256 tokenAmount, uint256 wrappedAmount);
    event Burn(address indexed sender, address indexed to, uint256 liquidity, uint256 tokenAmount, uint256 wrappedAmount);
    event Swap(
        address indexed sender,
        uint256 tokenIn,
        uint256 wrappedIn,
        uint256 tokenOut,
        uint256 wrappedOut,
        address indexed to
    );
    event Sync(uint112 reserveToken, uint112 reserveWrapped);

    error InsufficientLiquidityMinted();
    error InsufficientLiquidityBurned();
    error InsufficientLiquidity();
    error InvalidTo();
    error KInvariant();

    constructor(address _token, address _wrappedNative) {
        factory = msg.sender;
        token = _token;
        wrappedNative = _wrappedNative;
    }

    function getReserves() public view returns (uint112, uint112, uint32) {
        return (reserveToken, reserveWrapped, blockTimestampLast);
    }

    function _update(uint256 balanceToken, uint256 balanceWrapped) private {
        require(balanceToken <= type(uint112).max && balanceWrapped <= type(uint112).max, "Overflow");
        uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);
        uint112 _reserveToken = reserveToken;
        uint112 _reserveWrapped = reserveWrapped;
        if (_reserveToken != 0 && _reserveWrapped != 0) {
            uint32 timeElapsed = blockTimestamp - blockTimestampLast;
            if (timeElapsed > 0) {
                priceTokenCumulativeLast += uint256(_reserveWrapped) * 1e18 / uint256(_reserveToken) * timeElapsed;
                priceWrappedCumulativeLast += uint256(_reserveToken) * 1e18 / uint256(_reserveWrapped) * timeElapsed;
            }
        }
        reserveToken = uint112(balanceToken);
        reserveWrapped = uint112(balanceWrapped);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserveToken, reserveWrapped);
    }

    function _mint(address to, uint256 value) internal {
        totalSupply += value;
        balanceOf[to] += value;
    }

    function _burn(address from, uint256 value) internal {
        uint256 balance = balanceOf[from];
        if (balance < value) revert InsufficientLiquidityBurned();
        unchecked {
            balanceOf[from] = balance - value;
        }
        totalSupply -= value;
    }

    function mint(address to) external returns (uint256 liquidity) {
        (uint112 _reserveToken, uint112 _reserveWrapped, ) = getReserves();
        uint256 balanceToken = IERC20Minimal(token).balanceOf(address(this));
        uint256 balanceWrapped = IERC20Minimal(wrappedNative).balanceOf(address(this));
        uint256 amountToken = balanceToken - _reserveToken;
        uint256 amountWrapped = balanceWrapped - _reserveWrapped;

        if (totalSupply == 0) {
            liquidity = _sqrt(amountToken * amountWrapped) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY);
        } else {
            uint256 liquidityToken = amountToken * totalSupply / _reserveToken;
            uint256 liquidityWrapped = amountWrapped * totalSupply / _reserveWrapped;
            liquidity = liquidityToken < liquidityWrapped ? liquidityToken : liquidityWrapped;
        }
        if (liquidity == 0) revert InsufficientLiquidityMinted();
        _mint(to, liquidity);

        _update(balanceToken, balanceWrapped);
        kLast = uint256(reserveToken) * uint256(reserveWrapped);
        emit Mint(msg.sender, amountToken, amountWrapped);
    }

    function burn(address to) external returns (uint256 amountToken, uint256 amountWrapped) {
        (uint112 _reserveToken, uint112 _reserveWrapped, ) = getReserves();
        uint256 balanceToken = IERC20Minimal(token).balanceOf(address(this));
        uint256 balanceWrapped = IERC20Minimal(wrappedNative).balanceOf(address(this));
        uint256 liquidity = balanceOf[address(this)];

        uint256 _totalSupply = totalSupply;
        amountToken = liquidity * balanceToken / _totalSupply;
        amountWrapped = liquidity * balanceWrapped / _totalSupply;
        if (amountToken == 0 || amountWrapped == 0) revert InsufficientLiquidityBurned();

        _burn(address(this), liquidity);
        token.safeTransfer(to, amountToken);
        wrappedNative.safeTransfer(to, amountWrapped);

        balanceToken = IERC20Minimal(token).balanceOf(address(this));
        balanceWrapped = IERC20Minimal(wrappedNative).balanceOf(address(this));
        _update(balanceToken, balanceWrapped);
        kLast = uint256(reserveToken) * uint256(reserveWrapped);
        emit Burn(msg.sender, to, liquidity, amountToken, amountWrapped);
    }

    function swap(uint256 amountTokenOut, uint256 amountWrappedOut, address to) external {
        if (amountTokenOut == 0 && amountWrappedOut == 0) revert InsufficientLiquidity();
        (uint112 _reserveToken, uint112 _reserveWrapped, ) = getReserves();
        if (amountTokenOut > _reserveToken || amountWrappedOut > _reserveWrapped) revert InsufficientLiquidity();
        if (to == token || to == wrappedNative) revert InvalidTo();

        if (amountTokenOut > 0) token.safeTransfer(to, amountTokenOut);
        if (amountWrappedOut > 0) wrappedNative.safeTransfer(to, amountWrappedOut);

        uint256 balanceToken = IERC20Minimal(token).balanceOf(address(this));
        uint256 balanceWrapped = IERC20Minimal(wrappedNative).balanceOf(address(this));

        uint256 amountTokenIn = balanceToken > _reserveToken - amountTokenOut ? balanceToken - (_reserveToken - amountTokenOut) : 0;
        uint256 amountWrappedIn =
            balanceWrapped > _reserveWrapped - amountWrappedOut ? balanceWrapped - (_reserveWrapped - amountWrappedOut) : 0;
        if (amountTokenIn == 0 && amountWrappedIn == 0) revert InsufficientLiquidity();

        uint256 balanceTokenAdjusted = (balanceToken * FEE_DENOMINATOR) - (amountTokenIn * SWAP_FEE);
        uint256 balanceWrappedAdjusted = (balanceWrapped * FEE_DENOMINATOR) - (amountWrappedIn * SWAP_FEE);

        if (balanceTokenAdjusted * balanceWrappedAdjusted < uint256(_reserveToken) * uint256(_reserveWrapped) * FEE_DENOMINATOR ** 2) {
            revert KInvariant();
        }

        _update(balanceToken, balanceWrapped);
        emit Swap(msg.sender, amountTokenIn, amountWrappedIn, amountTokenOut, amountWrappedOut, to);
    }

    function skim(address to) external {
        token.safeTransfer(to, IERC20Minimal(token).balanceOf(address(this)) - reserveToken);
        wrappedNative.safeTransfer(to, IERC20Minimal(wrappedNative).balanceOf(address(this)) - reserveWrapped);
    }

    function sync() external {
        _update(IERC20Minimal(token).balanceOf(address(this)), IERC20Minimal(wrappedNative).balanceOf(address(this)));
    }

    function _sqrt(uint256 y) private pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
