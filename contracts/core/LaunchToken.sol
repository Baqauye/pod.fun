// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20Base} from "../libraries/ERC20Base.sol";

/// @title LaunchToken
/// @notice ERC20 template restricted to bonding curve until graduation.
contract LaunchToken is ERC20Base {
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 1e18;

    address public immutable factory;
    address public bondingCurve;
    address public controller;
    bool public tradingEnabled;

    mapping(address => bool) public allowlisted;

    event ControllerUpdated(address indexed controller);
    event TradingEnabled(address indexed executor);

    error NotAuthorized();
    error TradingLocked();

    constructor(string memory name_, string memory symbol_, address factory_)
        ERC20Base(name_, symbol_, 18)
    {
        require(factory_ != address(0), "INVALID_ADDRESS");
        factory = factory_;
        controller = factory_;
        allowlisted[factory_] = true;
        _mint(factory_, INITIAL_SUPPLY);
    }

    modifier onlyController() {
        if (msg.sender != controller) revert NotAuthorized();
        _;
    }

    function setController(address newController) external onlyController {
        require(newController != address(0), "INVALID_ADDRESS");
        controller = newController;
        allowlisted[newController] = true;
        emit ControllerUpdated(newController);
    }

    function enableTrading(address dexPair) external onlyController {
        require(!tradingEnabled, "ALREADY_ENABLED");
        tradingEnabled = true;
        allowlisted[dexPair] = true;
        controller = dexPair;
        emit TradingEnabled(msg.sender);
    }

    function configureBondingCurve(address bondingCurve_) external {
        if (msg.sender != factory) revert NotAuthorized();
        require(bondingCurve == address(0), "ALREADY_CONFIGURED");
        require(bondingCurve_ != address(0), "INVALID_ADDRESS");
        bondingCurve = bondingCurve_;
        allowlisted[bondingCurve_] = true;
        controller = bondingCurve_;
        emit ControllerUpdated(bondingCurve_);
        uint256 supply = balanceOf[factory];
        super._transfer(factory, bondingCurve_, supply);
    }

    function updateAllowlist(address account, bool allowed) external onlyController {
        allowlisted[account] = allowed;
    }

    function _transfer(address from, address to, uint256 value) internal override {
        if (!tradingEnabled) {
            if (!allowlisted[from] && !allowlisted[to]) revert TradingLocked();
        }
        super._transfer(from, to, value);
    }
}
