// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Script.sol";

/// @notice Entry point that delegates on-chain deployment to the Pod SDK helper.
/// @dev The heavy lifting lives in `script/deploy-with-pod.js`, which uses the Pod SDK
///      to broadcast legacy transactions constructed from Foundry build artifacts.
contract DeployScript is Script {
    function run() external {
        string memory projectRoot = vm.projectRoot();
        string[] memory cmd = new string[](3);
        cmd[0] = "node";
        cmd[1] = string.concat(projectRoot, "/script/deploy-with-pod.js");
        cmd[2] = projectRoot;

        // Executes the Node.js helper which performs deployment via the Pod SDK.
        vm.ffi(cmd);
    }
}
