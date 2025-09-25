# Pod.fun Launchpad Suite

Production-focused bonding curve launchpad and AMM stack targeting the pod network (pETH native).

## Contracts

| Contract | Purpose |
| --- | --- |
| `LaunchpadFactory` | Deploys ERC-20 launches with bonding curves, manages fees, graduation notifications. |
| `BondingCurve` | Handles primary market buys/sells with enforced fees and automated graduation to DEX. |
| `LaunchToken` | ERC-20 with restricted transfers pre-graduation and fixed 1B supply. |
| `DEXFactory` | Deterministic token/pETH pair deployment. |
| `DEXPair` | Constant-product AMM with 0.3% swap fee and TWAP data. |
| `DEXRouter` | Native/token swaps, liquidity management, deadline enforcement. |

## Development

1. Install dependencies (requires npm registry access):

```bash
npm install
```

2. Configure environment variables (copy `.env.example` to `.env` and update values).

3. Run the Hardhat test suite:

```bash
npm test
```

4. Compile contracts:

```bash
npm run compile
```

## Deployment Script

`deploy/00_deploy_core.js` deploys the DEX factory/router and launchpad configured for native pETH liquidity.

## Security Notes

- All privileged updates gated behind two-step ownership (`Ownable2Step`).
- Bonding curve disallows third-party manipulation pre-graduation and force notifies factory when migrating.
- Fees streamed to `feeRecipient`; graduation burns LP tokens by minting to zero address.
- Router enforces deadline-based slippage protection on user operations.
