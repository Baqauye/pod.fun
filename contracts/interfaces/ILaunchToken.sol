// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ILaunchToken {
    function factory() external view returns (address);
    function bondingCurve() external view returns (address);
    function controller() external view returns (address);
    function tradingEnabled() external view returns (bool);
    function allowlisted(address) external view returns (bool);
    function setController(address newController) external;
    function enableTrading(address dexPair) external;
    function updateAllowlist(address account, bool allowed) external;
    function configureBondingCurve(address bondingCurve) external;
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
}
