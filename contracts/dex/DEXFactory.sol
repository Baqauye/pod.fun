// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {DEXPair} from "./DEXPair.sol";

/// @title DEXFactory
/// @notice Deploys deterministic token/pETH pairs and manages protocol fee recipients.
contract DEXFactory {
    address public immutable protocolTreasury;
    address public owner;
    address public feeTo;

    mapping(address => address) public getPair;
    address[] public allPairs;

    event PairCreated(address indexed token, address pair);
    event OwnerUpdated(address indexed owner);
    event FeeToUpdated(address indexed feeTo);

    error Unauthorized();

    constructor(address treasury, address owner_) {
        require(treasury != address(0) && owner_ != address(0), "INVALID_ADDRESS");
        protocolTreasury = treasury;
        owner = owner_;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    function createPair(address token) external returns (address pair) {
        require(token != address(0), "INVALID_TOKEN");
        require(getPair[token] == address(0), "PAIR_EXISTS");
        bytes memory bytecode = abi.encodePacked(type(DEXPair).creationCode, abi.encode(token, address(this)));
        bytes32 salt = keccak256(abi.encode(token));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        require(pair != address(0), "CREATE_FAILED");
        getPair[token] = pair;
        allPairs.push(pair);
        emit PairCreated(token, pair);
    }

    function setOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "INVALID_ADDRESS");
        owner = newOwner;
        emit OwnerUpdated(newOwner);
    }

    function setFeeTo(address newFeeTo) external onlyOwner {
        feeTo = newFeeTo;
        emit FeeToUpdated(newFeeTo);
    }
}
