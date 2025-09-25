// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {LaunchToken} from "./LaunchToken.sol";
import {BondingCurve} from "./BondingCurve.sol";
import {ProtocolTreasury} from "./ProtocolTreasury.sol";
import {SafeTransferLib} from "../libraries/SafeTransferLib.sol";

/// @title LaunchpadFactory
/// @notice Deploys launch tokens, bonding curves, and routes fee management.
contract LaunchpadFactory {
    struct Launch {
        address token;
        address bondingCurve;
        address creator;
        uint64 launchedAt;
        bool graduated;
    }

    address public owner;
    address public pendingOwner;
    bool public paused;

    address public immutable dexFactory;
    address public immutable router;
    ProtocolTreasury public immutable treasury;

    uint256 public launchFeeBps = 400; // 4%
    uint256 public graduationTarget = 4 ether;
    uint256 public defaultInitialPrice = 0.001 ether;
    uint256 public defaultSlope = 1e12;

    Launch[] public launches;
    mapping(address => uint256) public tokenToLaunchId;

    event OwnershipTransferStarted(address indexed currentOwner, address indexed pendingOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Paused(address indexed executor, bool status);
    event LaunchCreated(uint256 indexed launchId, address token, address bondingCurve, address creator, uint256 curveFunding);
    event LaunchGraduated(uint256 indexed launchId, address token, address bondingCurve);
    event LaunchFeeUpdated(uint256 feeBps);
    event GraduationTargetUpdated(uint256 target);
    event DefaultCurveParamsUpdated(uint256 initialPrice, uint256 slope);

    error Unauthorized();
    error InvalidConfig();
    error PausedError();

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert PausedError();
        _;
    }

    constructor(address owner_, address dexFactory_, address router_, address guardian_) {
        require(owner_ != address(0) && dexFactory_ != address(0) && router_ != address(0), "INVALID_ADDRESS");
        owner = owner_;
        dexFactory = dexFactory_;
        router = router_;
        treasury = new ProtocolTreasury(address(this), guardian_);
    }

    function totalLaunches() external view returns (uint256) {
        return launches.length;
    }

    function launch(
        string calldata name,
        string calldata symbol,
        uint256 slope,
        uint256 initialPrice
    ) external payable whenNotPaused returns (address token, address bondingCurve) {
        require(bytes(name).length > 0 && bytes(symbol).length > 0, "INVALID_METADATA");
        uint256 feeBps = launchFeeBps;
        uint256 deposit = msg.value;
        require(deposit > 0, "NO_FUNDS");
        uint256 fee = (deposit * feeBps) / 10_000;
        uint256 curveFunding = deposit - fee;
        require(curveFunding > 0, "INSUFFICIENT_FUNDING");
        treasury.notifyFeeReceived{value: fee}();

        if (slope == 0) {
            slope = defaultSlope;
        }
        if (initialPrice == 0) {
            initialPrice = defaultInitialPrice;
        }

        LaunchToken launchToken = new LaunchToken(name, symbol, address(this));
        BondingCurve curve = new BondingCurve(
            address(this),
            address(launchToken),
            dexFactory,
            router,
            address(treasury),
            graduationTarget,
            initialPrice,
            slope
        );
        launchToken.configureBondingCurve(address(curve));
        SafeTransferLib.safeTransferNative(address(curve), curveFunding);

        launches.push(
            Launch({
                token: address(launchToken),
                bondingCurve: address(curve),
                creator: msg.sender,
                launchedAt: uint64(block.timestamp),
                graduated: false
            })
        );
        uint256 launchId = launches.length - 1;
        tokenToLaunchId[address(launchToken)] = launchId;

        emit LaunchCreated(launchId, address(launchToken), address(curve), msg.sender, curveFunding);
        token = address(launchToken);
        bondingCurve = address(curve);
    }

    function notifyGraduation(address token) external {
        uint256 launchId = tokenToLaunchId[token];
        Launch storage info = launches[launchId];
        require(info.bondingCurve == msg.sender, "UNAUTHORIZED_CALLER");
        info.graduated = true;
        emit LaunchGraduated(launchId, token, msg.sender);
    }

    function setLaunchFee(uint256 feeBps) external onlyOwner {
        require(feeBps <= 1000, "FEE_TOO_HIGH");
        launchFeeBps = feeBps;
        emit LaunchFeeUpdated(feeBps);
    }

    function setGraduationTarget(uint256 target) external onlyOwner {
        require(target >= 1 ether, "TARGET_TOO_LOW");
        graduationTarget = target;
        emit GraduationTargetUpdated(target);
    }

    function setDefaultCurveParams(uint256 initialPrice, uint256 slope) external onlyOwner {
        require(initialPrice > 0 && slope > 0, "INVALID_PARAMS");
        defaultInitialPrice = initialPrice;
        defaultSlope = slope;
        emit DefaultCurveParamsUpdated(initialPrice, slope);
    }

    function setPaused(bool status) external onlyOwner {
        paused = status;
        emit Paused(msg.sender, status);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "NOT_PENDING_OWNER");
        address previousOwner = owner;
        owner = pendingOwner;
        pendingOwner = address(0);
        emit OwnershipTransferred(previousOwner, owner);
    }
}
