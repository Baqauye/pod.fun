// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ReentrancyGuard} from "../libraries/ReentrancyGuard.sol";
import {SafeTransferLib} from "../libraries/SafeTransferLib.sol";

/// @title ProtocolTreasury
/// @notice Collects and distributes protocol fees in pETH.
contract ProtocolTreasury is ReentrancyGuard {
    address public immutable factory;
    address public guardian;

    event GuardianUpdated(address indexed guardian);
    event FeesWithdrawn(address indexed to, uint256 amount);

    error NotAuthorized();

    constructor(address _factory, address _guardian) {
        require(_factory != address(0) && _guardian != address(0), "INVALID_ADDRESS");
        factory = _factory;
        guardian = _guardian;
    }

    modifier onlyFactory() {
        if (msg.sender != factory) revert NotAuthorized();
        _;
    }

    modifier onlyGuardian() {
        if (msg.sender != guardian) revert NotAuthorized();
        _;
    }

    function updateGuardian(address newGuardian) external onlyGuardian {
        require(newGuardian != address(0), "INVALID_ADDRESS");
        guardian = newGuardian;
        emit GuardianUpdated(newGuardian);
    }

    function sweep(address to, uint256 amount) external onlyGuardian nonReentrant {
        require(to != address(0), "INVALID_ADDRESS");
        SafeTransferLib.safeTransferNative(to, amount);
        emit FeesWithdrawn(to, amount);
    }

    receive() external payable {}

    function notifyFeeReceived() external payable onlyFactory {}
}
