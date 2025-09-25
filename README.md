# Pod.fun Contracts

Comprehensive launchpad and DEX stack for pETH-native chains. The system bootstraps projects through a bonding curve and locks liquidity into an automated market maker upon graduation.

## Packages
- **contracts/** – Solidity sources for launchpad, bonding curve, DEX, and shared libraries.
- **scripts/** – Hardhat deployment helper (offline-ready).
- **script/** – Foundry deployment entry points and Pod SDK bridge.
- **test/** – Static configuration checks executed via `npm test`.
- **docs/** – Architecture overview and integration notes.

## Requirements
- Node.js 18+
- Hardhat (optional, required for Solidity compilation)
- Foundry (optional, required for Foundry-driven scripting)

## Usage
```bash
npm install # optional if registry access is available
npm test
```

To deploy contracts once Hardhat dependencies are installed:
```bash
npx hardhat run --network <network> scripts/deploy.js
```

### Foundry + Pod SDK workflow
| Step | Command | Notes |
| ---- | ------- | ----- |
| 1 | `forge build` | Aligns bytecode/ABIs with Hardhat (solc 0.8.19, 800 optimizer runs). |
| 2 | `export POD_RPC_URL=...`<br>`export POD_PRIVATE_KEY=0x...`<br>`export POD_GUARDIAN_ADDRESS=0x...` | Guardian defaults to the broadcaster when unset. Keep keys outside shell history. |
| 3 | `forge script script/Deploy.s.sol:DeployScript --ffi --broadcast` | Delegates to `script/deploy-with-pod.js`, which composes legacy `PodTransactionRequest`s and persists `deployment-foundry.json`. |

The helper script enforces legacy transactions through `PodProviderBuilder` and writes deployment metadata mirroring the Hardhat flow. Supply `--legacy` if your Foundry toolchain requires explicit flags.

### Environment Variables (`.env`)
- `deployer_private_key`
- `peth_rpc_url`
- `protocol_guardian_address`
- `POD_PRIVATE_KEY`
- `POD_RPC_URL`
- `POD_GUARDIAN_ADDRESS`

## Security Practices
- All state-mutating endpoints include validation, reentrancy guards, and emergency pause controls.
- Fees are routed to `ProtocolTreasury`, enabling guardian-controlled sweeps.
- Liquidity is permanently locked after graduation via LP token burning.
