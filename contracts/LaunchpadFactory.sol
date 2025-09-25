// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable2Step} from "./utils/Ownable.sol";
import {LaunchToken} from "./LaunchToken.sol";
import {BondingCurve} from "./BondingCurve.sol";
import {DEXFactory} from "./DEXFactory.sol";
import {IWrappedNative} from "./interfaces/IWrappedNative.sol";

/// @title LaunchpadFactory
/// @notice Deploys bonding curve + token pairs with configurable economic parameters.
contract LaunchpadFactory is Ownable2Step {
    struct LaunchInfo {
        address creator;
        address token;
        address bondingCurve;
        bool graduated;
    }

    uint256 public immutable graduationThreshold;
    uint256 public immutable launchFeeBps;
    uint256 public immutable buyFeeBps;
    uint256 public immutable sellFeeBps;

    address public feeRecipient;
    DEXFactory public dexFactory;
    IWrappedNative public wrappedNative;

    LaunchInfo[] public launches;

    event LaunchCreated(uint256 indexed launchId, address indexed creator, address token, address bondingCurve);
    event FeeRecipientUpdated(address indexed newRecipient);
    event DexFactoryUpdated(address indexed newFactory);
    event WrappedNativeUpdated(address indexed newWrapped);
    event LaunchGraduated(uint256 indexed launchId);

    error InvalidNativeValue();

    constructor(
        address owner_,
        address feeRecipient_,
        DEXFactory dexFactory_,
        IWrappedNative wrappedNative_,
        uint256 graduationThreshold_,
        uint256 launchFeeBps_,
        uint256 buyFeeBps_,
        uint256 sellFeeBps_
    ) Ownable2Step(owner_) {
        require(address(dexFactory_) != address(0) && address(wrappedNative_) != address(0), "ZeroAddress");
        require(feeRecipient_ != address(0), "ZeroRecipient");
        feeRecipient = feeRecipient_;
        dexFactory = dexFactory_;
        wrappedNative = wrappedNative_;
        graduationThreshold = graduationThreshold_;
        launchFeeBps = launchFeeBps_;
        buyFeeBps = buyFeeBps_;
        sellFeeBps = sellFeeBps_;
    }

    function setFeeRecipient(address newRecipient) external onlyOwner {
        require(newRecipient != address(0), "ZeroRecipient");
        feeRecipient = newRecipient;
        emit FeeRecipientUpdated(newRecipient);
    }

    function setDexFactory(DEXFactory newFactory) external onlyOwner {
        require(address(newFactory) != address(0), "ZeroFactory");
        dexFactory = newFactory;
        emit DexFactoryUpdated(address(newFactory));
    }

    function setWrappedNative(IWrappedNative newWrapped) external onlyOwner {
        require(address(newWrapped) != address(0), "ZeroWrapped");
        wrappedNative = newWrapped;
        emit WrappedNativeUpdated(address(newWrapped));
    }

    function launchesLength() external view returns (uint256) {
        return launches.length;
    }

    function createLaunch(string calldata name, string calldata symbol)
        external
        payable
        returns (uint256 launchId, address token, address curve)
    {
        if (msg.value == 0) revert InvalidNativeValue();

        launchId = launches.length;
        token = address(new LaunchToken(name, symbol, address(this)));
        curve = address(new BondingCurve(
            LaunchToken(token),
            this,
            dexFactory,
            wrappedNative,
            feeRecipient,
            launchFeeBps,
            buyFeeBps,
            sellFeeBps,
            graduationThreshold,
            launchId
        ));

        LaunchToken(token).setBondingCurve(curve);
        LaunchToken(token).transfer(curve, LaunchToken(token).balanceOf(address(this)));
        (bool success, ) = curve.call{value: msg.value}(abi.encodeWithSignature("initialize(address)", msg.sender));
        require(success, "InitFailed");

        launches.push(LaunchInfo({creator: msg.sender, token: token, bondingCurve: curve, graduated: false}));
        emit LaunchCreated(launchId, msg.sender, token, curve);
    }

    function notifyGraduation(uint256 launchId) external {
        LaunchInfo storage info = launches[launchId];
        require(msg.sender == info.bondingCurve, "OnlyCurve");
        if (!info.graduated) {
            info.graduated = true;
            emit LaunchGraduated(launchId);
        }
    }
}
