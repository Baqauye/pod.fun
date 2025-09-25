// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20Base} from "../libraries/ERC20Base.sol";
import {ReentrancyGuard} from "../libraries/ReentrancyGuard.sol";
import {SafeTransferLib} from "../libraries/SafeTransferLib.sol";
import {MathLib} from "../libraries/MathLib.sol";

/// @title DEXPair
/// @notice Constant product AMM for token/pETH pairs.
contract DEXPair is ERC20Base, ReentrancyGuard {
    using MathLib for uint256;

    address public immutable factory;
    address public immutable token;

    uint256 public reserveToken;
    uint256 public reservePEth;
    uint32 public blockTimestampLast;

    uint256 public constant MINIMUM_LIQUIDITY = 1e3;
    uint256 private constant FEE_DENOMINATOR = 1000;
    uint256 private constant FEE_RATE = 3; // 0.3%

    mapping(address => uint256) public nonces;
    bytes32 public immutable DOMAIN_SEPARATOR;
    bytes32 private constant PERMIT_TYPEHASH =
        0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    event Mint(address indexed sender, uint256 amountToken, uint256 amountPEth);
    event Burn(address indexed sender, address indexed to, uint256 amountToken, uint256 amountPEth);
    event Swap(
        address indexed sender,
        address indexed to,
        bool tokenOut,
        uint256 amountOut,
        uint256 amountIn
    );
    event Sync(uint256 reserveToken, uint256 reservePEth);

    modifier onlyFactory() {
        require(msg.sender == factory, "FORBIDDEN");
        _;
    }

    constructor(address token_, address factory_) ERC20Base("Pod.fun LP", "POD-LP", 18) {
        require(token_ != address(0) && factory_ != address(0), "INVALID_ADDRESS");
        token = token_;
        factory = factory_;
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes("1")),
                chainId,
                address(this)
            )
        );
    }

    function _update(uint256 balanceToken, uint256 balancePEth) private {
        reserveToken = balanceToken;
        reservePEth = balancePEth;
        blockTimestampLast = uint32(block.timestamp);
        emit Sync(reserveToken, reservePEth);
    }

    function mint(address to) external nonReentrant returns (uint256 liquidity) {
        require(to != address(0), "INVALID_TO");
        uint256 balanceToken = IERC20(token).balanceOf(address(this));
        uint256 balancePEth = address(this).balance;
        uint256 amountToken = balanceToken - reserveToken;
        uint256 amountPEth = balancePEth - reservePEth;
        require(amountToken > 0 && amountPEth > 0, "INSUFFICIENT_LIQUIDITY_IN");

        uint256 _totalSupply = totalSupply;
        if (_totalSupply == 0) {
            liquidity = MathLib.sqrt(amountToken * amountPEth) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY);
        } else {
            liquidity = MathLib.min((amountToken * _totalSupply) / reserveToken, (amountPEth * _totalSupply) / reservePEth);
        }
        require(liquidity > 0, "INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);

        _update(balanceToken, balancePEth);
        emit Mint(msg.sender, amountToken, amountPEth);
    }

    function burn(address to) external nonReentrant returns (uint256 amountToken, uint256 amountPEth) {
        require(to != address(0), "INVALID_TO");
        uint256 balanceToken = IERC20(token).balanceOf(address(this));
        uint256 balancePEth = address(this).balance;
        uint256 liquidity = balanceOf[address(this)];

        uint256 _totalSupply = totalSupply;
        amountToken = (liquidity * balanceToken) / _totalSupply;
        amountPEth = (liquidity * balancePEth) / _totalSupply;
        require(amountToken > 0 && amountPEth > 0, "INSUFFICIENT_LIQUIDITY_BURNED");
        _burn(address(this), liquidity);

        SafeTransferLib.safeTransfer(token, to, amountToken);
        SafeTransferLib.safeTransferNative(to, amountPEth);

        balanceToken = IERC20(token).balanceOf(address(this));
        balancePEth = address(this).balance;
        _update(balanceToken, balancePEth);
        emit Burn(msg.sender, to, amountToken, amountPEth);
    }

    function lockLiquidity(uint256 amount) external {
        require(amount > 0, "INVALID_AMOUNT");
        require(balanceOf[msg.sender] >= amount, "INSUFFICIENT_BALANCE");
        balanceOf[msg.sender] -= amount;
        totalSupply -= amount;
        emit Transfer(msg.sender, address(0), amount);
    }

    function swap(address to, bool tokenOut, uint256 amountOut, address payer)
        external
        nonReentrant
        returns (uint256 amountIn)
    {
        require(amountOut > 0, "INSUFFICIENT_OUTPUT");
        require(to != address(0) && payer != address(0), "INVALID_PARAMS");

        uint256 _reserveToken = reserveToken;
        uint256 _reservePEth = reservePEth;
        require(_reserveToken > 0 && _reservePEth > 0, "INSUFFICIENT_LIQUIDITY");

        if (tokenOut) {
            require(amountOut < _reserveToken, "EXCESS_OUTPUT");
            SafeTransferLib.safeTransfer(token, to, amountOut);
            uint256 balanceToken = IERC20(token).balanceOf(address(this));
            uint256 balancePEth = address(this).balance;
            amountIn = balancePEth - _reservePEth;
            require(amountIn > 0, "INSUFFICIENT_INPUT");
            uint256 balanceTokenAdjusted = balanceToken * FEE_DENOMINATOR;
            uint256 balancePEthAdjusted = (balancePEth * FEE_DENOMINATOR) - (amountIn * FEE_RATE);
            require(balanceTokenAdjusted * balancePEthAdjusted >= _reserveToken * _reservePEth * (FEE_DENOMINATOR**2), "K");
        } else {
            require(amountOut < _reservePEth, "EXCESS_OUTPUT");
            SafeTransferLib.safeTransferNative(to, amountOut);
            uint256 balanceToken = IERC20(token).balanceOf(address(this));
            uint256 balancePEth = address(this).balance;
            amountIn = balanceToken - _reserveToken;
            require(amountIn > 0, "INSUFFICIENT_INPUT");
            uint256 balanceTokenAdjusted = (balanceToken * FEE_DENOMINATOR) - (amountIn * FEE_RATE);
            uint256 balancePEthAdjusted = balancePEth * FEE_DENOMINATOR;
            require(balanceTokenAdjusted * balancePEthAdjusted >= _reserveToken * _reservePEth * (FEE_DENOMINATOR**2), "K");
        }

        uint256 balanceTokenAfter = IERC20(token).balanceOf(address(this));
        uint256 balancePEthAfter = address(this).balance;
        _update(balanceTokenAfter, balancePEthAfter);
        emit Swap(msg.sender, to, tokenOut, amountOut, amountIn);
    }

    function sync() external nonReentrant {
        _update(IERC20(token).balanceOf(address(this)), address(this).balance);
    }

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(deadline >= block.timestamp, "PERMIT_EXPIRED");
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(
                        PERMIT_TYPEHASH,
                        owner,
                        spender,
                        value,
                        nonces[owner]++,
                        deadline
                    )
                )
            )
        );
        address recovered = ecrecover(digest, v, r, s);
        require(recovered != address(0) && recovered == owner, "INVALID_SIGNATURE");
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    receive() external payable {}
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
}
