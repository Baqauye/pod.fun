// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IBondingCurve {
    function buy(uint256 tokenAmountOut, uint256 maxPayment, address recipient) external payable returns (uint256 cost, uint256 fee);
    function sell(uint256 tokenAmountIn, uint256 minPayout, address recipient) external returns (uint256 proceeds, uint256 fee);
    function graduate() external;
    function isGraduated() external view returns (bool);
}
