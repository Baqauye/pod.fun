// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

library Create2 {
    function computeAddress(bytes32 salt, bytes32 bytecodeHash, address deployer) internal pure returns (address) {
        bytes32 data = keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, bytecodeHash));
        return address(uint160(uint256(data)));
    }
}
