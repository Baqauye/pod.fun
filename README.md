# Pod.fun Contracts

Comprehensive launchpad and DEX stack for pETH-native chains. The system bootstraps projects through a bonding curve and locks liquidity into an automated market maker upon graduation.

## Packages
- **contracts/** – Solidity sources for launchpad, bonding curve, DEX, and shared libraries.
- **scripts/** – Hardhat deployment helper (offline-ready).
- **test/** – Static configuration checks executed via `npm test`.
- **docs/** – Architecture overview and integration notes.

## Requirements
- Node.js 18+
- Hardhat (optional, required for Solidity compilation)

## Usage
```bash
npm install # optional if registry access is available
npm test
```

To deploy contracts once Hardhat dependencies are installed:
```bash
npx hardhat run --network <network> scripts/deploy.js
```

### Environment Variables (`.env`)
- `deployer_private_key`
- `peth_rpc_url`
- `protocol_guardian_address`

## Security Practices
- All state-mutating endpoints include validation, reentrancy guards, and emergency pause controls.
- Fees are routed to `ProtocolTreasury`, enabling guardian-controlled sweeps.
- Liquidity is permanently locked after graduation via LP token burning.
