// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title SafeTransferLib
/// @notice Minimal ERC20 transfer helper with native pETH support.
library SafeTransferLib {
    error SafeTransferFailed();
    error SafeApproveFailed();

    function safeTransfer(address token, address to, uint256 value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) revert SafeTransferFailed();
    }

    function safeTransferFrom(address token, address from, address to, uint256 value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) revert SafeTransferFailed();
    }

    function safeApprove(address token, address spender, uint256 value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, spender, value));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) revert SafeApproveFailed();
    }

    function safeTransferNative(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}("");
        if (!success) revert SafeTransferFailed();
    }
}
