// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IDEXPair {
    function factory() external view returns (address);
    function token() external view returns (address);
    function reserveToken() external view returns (uint256);
    function reservePEth() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function mint(address to) external returns (uint256 liquidity);
    function burn(address to) external returns (uint256 amountToken, uint256 amountPEth);
    function lockLiquidity(uint256 amount) external;
    function sync() external;
    function swap(address to, bool tokenOut, uint256 amountOut, address payer) external returns (uint256 amountIn);
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;
}
