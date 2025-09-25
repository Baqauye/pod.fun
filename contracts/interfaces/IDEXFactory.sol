// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IDEXFactory {
    event PairCreated(address indexed token, address pair);

    function protocolTreasury() external view returns (address);
    function feeTo() external view returns (address);
    function getPair(address token) external view returns (address);
    function createPair(address token) external returns (address pair);
    function setFeeTo(address newFeeTo) external;
}
