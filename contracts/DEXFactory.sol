// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable2Step} from "./utils/Ownable.sol";
import {DEXPair} from "./DEXPair.sol";

/// @title DEXFactory
/// @notice Creates deterministic token/pETH pools for graduated launches.
contract DEXFactory is Ownable2Step {
    address public immutable wrappedNative;
    mapping(address => address) public getPair; // token => pair
    address[] public allPairs;

    bytes32 public immutable pairCodeHash;
    address public feeRecipient;

    event PairCreated(address indexed token, address pair, uint256 index);
    event FeeRecipientUpdated(address indexed newRecipient);

    constructor(address wrappedNative_, address owner_) Ownable2Step(owner_) {
        require(wrappedNative_ != address(0), "WrappedZero");
        wrappedNative = wrappedNative_;
        pairCodeHash = keccak256(type(DEXPair).creationCode);
    }

    function setFeeRecipient(address newRecipient) external onlyOwner {
        require(newRecipient != address(0), "RecipientZero");
        feeRecipient = newRecipient;
        emit FeeRecipientUpdated(newRecipient);
    }

    function createPair(address token) external returns (address pair) {
        require(token != address(0), "TokenZero");
        require(getPair[token] == address(0), "PairExists");

        pair = address(new DEXPair{salt: keccak256(abi.encode(token))}(token, wrappedNative));
        getPair[token] = pair;
        allPairs.push(pair);
        emit PairCreated(token, pair, allPairs.length - 1);
    }

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }
}
