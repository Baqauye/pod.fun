// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable2Step} from "./Ownable.sol";

/// @title ERC20
/// @notice Gas-focused ERC20 implementation with hooks for transfer restrictions.
contract ERC20 is Ownable2Step {
    string public name;
    string public symbol;
    uint8 public immutable decimals;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    error InsufficientBalance();
    error InsufficientAllowance();

    constructor(string memory _name, string memory _symbol, uint8 _decimals, address _owner)
        Ownable2Step(_owner)
    {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            if (allowed < value) revert InsufficientAllowance();
            allowance[from][msg.sender] = allowed - value;
        }
        _transfer(from, to, value);
        return true;
    }

    function _approve(address owner_, address spender, uint256 value) internal {
        allowance[owner_][spender] = value;
        emit Approval(owner_, spender, value);
    }

    function _transfer(address from, address to, uint256 value) internal virtual {
        if (balanceOf[from] < value) revert InsufficientBalance();
        _beforeTokenTransfer(from, to);
        unchecked {
            balanceOf[from] -= value;
            balanceOf[to] += value;
        }
        emit Transfer(from, to, value);
    }

    function _mint(address to, uint256 value) internal {
        _beforeTokenTransfer(address(0), to);
        totalSupply += value;
        balanceOf[to] += value;
        emit Transfer(address(0), to, value);
    }

    function _burn(address from, uint256 value) internal {
        if (balanceOf[from] < value) revert InsufficientBalance();
        _beforeTokenTransfer(from, address(0));
        unchecked {
            balanceOf[from] -= value;
            totalSupply -= value;
        }
        emit Transfer(from, address(0), value);
    }

    function _beforeTokenTransfer(address from, address to) internal virtual {}
}
