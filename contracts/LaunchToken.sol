// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "./utils/ERC20.sol";

/// @title LaunchToken
/// @notice ERC20 with bonding-curve restricted transfers until graduation.
contract LaunchToken is ERC20 {
    address public bondingCurve;
    bool public tradingEnabled;

    event BondingCurveSet(address indexed bondingCurve);
    event TradingEnabled();

    error TradingLocked();
    error BondingCurveOnly();

    uint256 private constant TOTAL_SUPPLY = 1_000_000_000 ether; // 1B tokens, 18 decimals

    constructor(string memory name_, string memory symbol_, address owner_)
        ERC20(name_, symbol_, 18, owner_)
    {
        _mint(owner_, TOTAL_SUPPLY);
    }

    function setBondingCurve(address bondingCurve_) external onlyOwner {
        require(bondingCurve_ != address(0), "CurveZero");
        bondingCurve = bondingCurve_;
        emit BondingCurveSet(bondingCurve_);
    }

    function enableTrading() external {
        if (msg.sender != bondingCurve) revert BondingCurveOnly();
        tradingEnabled = true;
        emit TradingEnabled();
    }

    function _beforeTokenTransfer(address from, address to) internal view override {
        if (tradingEnabled) return;
        if (from == address(0) || to == address(0)) return; // allow mint/burn pre-launch
        if (from != bondingCurve && to != bondingCurve) revert TradingLocked();
    }
}
