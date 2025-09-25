// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SafeTransferLib} from "./utils/SafeTransferLib.sol";

interface IERC20Minimal {
    function balanceOf(address) external view returns (uint256);
}

/// @title DEXPair
/// @notice Uniswap V2 style constant-product AMM pair that holds native pETH liquidity directly.
contract DEXPair {
    using SafeTransferLib for address;

    uint256 private constant MINIMUM_LIQUIDITY = 1e3;
    uint256 private constant FEE_DENOMINATOR = 1000;
    uint256 private constant SWAP_FEE = 3; // 0.3%

    address public immutable factory;
    address public immutable token;

    uint112 private reserveToken;
    uint112 private reserveNative;
    uint32 private blockTimestampLast;

    uint256 public priceTokenCumulativeLast;
    uint256 public priceNativeCumulativeLast;
    uint256 public kLast;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;

    event Mint(address indexed sender, uint256 tokenAmount, uint256 nativeAmount);
    event Burn(address indexed sender, address indexed to, uint256 liquidity, uint256 tokenAmount, uint256 nativeAmount);
    event Swap(
        address indexed sender,
        uint256 tokenIn,
        uint256 nativeIn,
        uint256 tokenOut,
        uint256 nativeOut,
        address indexed to
    );
    event Sync(uint112 reserveToken, uint112 reserveNative);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    error InsufficientLiquidityMinted();
    error InsufficientLiquidityBurned();
    error InsufficientLiquidity();
    error InvalidTo();
    error KInvariant();
    error InsufficientBalance();
    error AllowanceExceeded();

    constructor(address _token) {
        factory = msg.sender;
        token = _token;
    }

    receive() external payable {}

    function getReserves() public view returns (uint112, uint112, uint32) {
        return (reserveToken, reserveNative, blockTimestampLast);
    }

    function _update(uint256 balanceToken, uint256 balanceNative) private {
        require(balanceToken <= type(uint112).max && balanceNative <= type(uint112).max, "Overflow");
        uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);
        uint112 _reserveToken = reserveToken;
        uint112 _reserveNative = reserveNative;
        if (_reserveToken != 0 && _reserveNative != 0) {
            uint32 timeElapsed = blockTimestamp - blockTimestampLast;
            if (timeElapsed > 0) {
                priceTokenCumulativeLast += uint256(_reserveNative) * 1e18 / uint256(_reserveToken) * timeElapsed;
                priceNativeCumulativeLast += uint256(_reserveToken) * 1e18 / uint256(_reserveNative) * timeElapsed;
            }
        }
        reserveToken = uint112(balanceToken);
        reserveNative = uint112(balanceNative);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserveToken, reserveNative);
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
        (uint112 _reserveToken, uint112 _reserveNative, ) = getReserves();
        uint256 balanceToken = IERC20Minimal(token).balanceOf(address(this));
        uint256 balanceNative = address(this).balance;
        uint256 amountToken = balanceToken - _reserveToken;
        uint256 amountNative = balanceNative - _reserveNative;

        if (totalSupply == 0) {
            liquidity = _sqrt(amountToken * amountNative) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY);
        } else {
            uint256 liquidityToken = amountToken * totalSupply / _reserveToken;
            uint256 liquidityNative = amountNative * totalSupply / _reserveNative;
            liquidity = liquidityToken < liquidityNative ? liquidityToken : liquidityNative;
        }
        if (liquidity == 0) revert InsufficientLiquidityMinted();
        _mint(to, liquidity);

        _update(balanceToken, balanceNative);
        kLast = uint256(reserveToken) * uint256(reserveNative);
        emit Mint(msg.sender, amountToken, amountNative);
    }

    function burn(address to) external returns (uint256 amountToken, uint256 amountNative) {
        (uint112 _reserveToken, uint112 _reserveNative, ) = getReserves();
        uint256 balanceToken = IERC20Minimal(token).balanceOf(address(this));
        uint256 balanceNative = address(this).balance;
        uint256 liquidity = balanceOf[address(this)];

        uint256 _totalSupply = totalSupply;
        amountToken = liquidity * balanceToken / _totalSupply;
        amountNative = liquidity * balanceNative / _totalSupply;
        if (amountToken == 0 || amountNative == 0) revert InsufficientLiquidityBurned();

        _burn(address(this), liquidity);
        token.safeTransfer(to, amountToken);
        SafeTransferLib.safeTransferETH(to, amountNative);

        balanceToken = IERC20Minimal(token).balanceOf(address(this));
        balanceNative = address(this).balance;
        _update(balanceToken, balanceNative);
        kLast = uint256(reserveToken) * uint256(reserveNative);
        emit Burn(msg.sender, to, liquidity, amountToken, amountNative);
    }

    function swap(uint256 amountTokenOut, uint256 amountNativeOut, address to) external payable {
        if (amountTokenOut == 0 && amountNativeOut == 0) revert InsufficientLiquidity();
        (uint112 _reserveToken, uint112 _reserveNative, ) = getReserves();
        if (amountTokenOut > _reserveToken || amountNativeOut > _reserveNative) revert InsufficientLiquidity();
        if (to == token) revert InvalidTo();

        if (amountTokenOut > 0) token.safeTransfer(to, amountTokenOut);
        if (amountNativeOut > 0) SafeTransferLib.safeTransferETH(to, amountNativeOut);

        uint256 balanceToken = IERC20Minimal(token).balanceOf(address(this));
        uint256 balanceNative = address(this).balance;

        uint256 amountTokenIn = balanceToken > _reserveToken - amountTokenOut ? balanceToken - (_reserveToken - amountTokenOut) : 0;
        uint256 amountNativeIn =
            balanceNative > _reserveNative - amountNativeOut ? balanceNative - (_reserveNative - amountNativeOut) : 0;
        if (amountTokenIn == 0 && amountNativeIn == 0) revert InsufficientLiquidity();

        uint256 balanceTokenAdjusted = (balanceToken * FEE_DENOMINATOR) - (amountTokenIn * SWAP_FEE);
        uint256 balanceNativeAdjusted = (balanceNative * FEE_DENOMINATOR) - (amountNativeIn * SWAP_FEE);

        if (balanceTokenAdjusted * balanceNativeAdjusted < uint256(_reserveToken) * uint256(_reserveNative) * FEE_DENOMINATOR**2) {
            revert KInvariant();
        }

        _update(balanceToken, balanceNative);
        emit Swap(msg.sender, amountTokenIn, amountNativeIn, amountTokenOut, amountNativeOut, to);
    }

    function skim(address to) external {
        token.safeTransfer(to, IERC20Minimal(token).balanceOf(address(this)) - reserveToken);
        SafeTransferLib.safeTransferETH(to, address(this).balance - reserveNative);
    }

    function sync() external {
        _update(IERC20Minimal(token).balanceOf(address(this)), address(this).balance);
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed < value) revert AllowanceExceeded();
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - value;
            emit Approval(from, msg.sender, allowance[from][msg.sender]);
        }
        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) internal {
        if (to == address(0)) revert InvalidTo();
        uint256 balance = balanceOf[from];
        if (balance < value) revert InsufficientBalance();
        unchecked {
            balanceOf[from] = balance - value;
            balanceOf[to] += value;
        }
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
