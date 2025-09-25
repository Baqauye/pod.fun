// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IProtocolTreasury {
    function factory() external view returns (address);
    function guardian() external view returns (address);
    function notifyFeeReceived() external payable;
    function sweep(address to, uint256 amount) external;
}
