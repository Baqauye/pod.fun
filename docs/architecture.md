# Pod.fun Launchpad Architecture

## Overview
Pod.fun provides a self-contained launchpad and DEX stack tailored for a pETH-native chain. Projects launch through a bonding curve phase and graduate into a permanent AMM pool once the curated market cap target is achieved.

## Components

| Contract | Responsibility |
| --- | --- |
| `LaunchpadFactory` | Deploys launches, maintains configuration, forwards fees to the treasury, and tracks graduation state. |
| `BondingCurve` | Linear bonding curve implementing buy/sell logic with protocol fees, graduation checks, and liquidity migration into the DEX. |
| `LaunchToken` | ERC20 template with a 1B fixed supply, transfer allowlisting prior to graduation, and automatic controller reassignment to the DEX pair. |
| `ProtocolTreasury` | Receives launch fees, buy/sell fees, and allows guardian-controlled withdrawals. |
| `DEXFactory` | Deploys deterministic `DEXPair` instances per token and manages fee recipient configuration. |
| `DEXPair` | Constant-product AMM specialised for token/pETH pairs, issuing LP shares with on-chain permit support. |
| `DEXRouter` | Adds/removes liquidity, executes swaps, and exposes helper pricing math while enforcing deadlines. |

## Launch Lifecycle

1. **Launch** – Teams call `LaunchpadFactory.launch` with metadata and optional custom bonding-curve parameters. A 4% fee is split to the treasury and the remaining pETH bootstraps the curve.
2. **Bonding Curve Trading** – Participants buy/sell tokens via the bonding curve. Buys pay a 5% fee, sells pay a 1% fee, and the contract tracks circulating supply alongside the pETH reserve.
3. **Graduation** – When `marketCap()` exceeds the configured threshold (default 4 pETH), the bonding curve deploys/uses a `DEXPair`, migrates all reserves, burns the LP tokens, and enables free trading on the DEX.

## Security Considerations

- Reentrancy guards protect state-changing entry points across curve and AMM contracts.
- Strict access control modifiers cover configuration mutations.
- Launch fees and curve fees flow into the treasury with guardian-controlled withdrawals.
- Router functions enforce deadlines and minimum outputs to prevent stale slippage exploits.
- LP token burning ensures liquidity is permanently locked after graduation.

## Gas Optimisation Highlights

- Storage reads cached in local variables before updates (e.g. bonding curve pricing, AMM reserve syncs).
- Math helper `MathLib.mulDiv` avoids redundant intermediate allocations while preserving precision.
- Create2 is unnecessary because the factory instantiates contracts sequentially, reducing deployment bytecode complexity.

## Extensibility

- Additional MEV resistance (e.g. commit/reveal) can be layered into the router without touching the bonding curve.
- Treasury sweeping logic can be extended to stream fees or split among multiple recipients.
- Launch factory exposes parameter setters to adjust slope/price defaults as network conditions evolve.
