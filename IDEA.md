im building on a chain that doesn't have any existing DEXs yet, so the launchpad needs to include DEX functionality as part of the graduation process.
Modified Architecture for Chains Without DEXs
Since there's no Uniswap/PancakeSwap to graduate to, your launchpad needs to create its own DEX infrastructure:
Core Contracts Needed:
1. Factory Contract
Creates new token launches
Stores global configuration
Tracks all launched tokens
Manages graduation thresholds
2. Bonding Curve Contract (per token)
Handles initial trading via mathematical curve
Manages token supply and pETH reserves
Triggers graduation when conditions are met
Migrates liquidity to DEX pool upon graduation
3. Token Contract (ERC-20)
Standard ERC-20 implementation
Initially restricted to bonding curve trading only
Unrestricted transfers after graduation
4. DEX Factory Contract
Creates new trading pairs for graduated tokens
Similar to Uniswap V2 Factory
Manages pair creation and tracking
5. DEX Pair Contract
Individual AMM pools for each token/pETH pair
Implements constant product formula (x * y = k)
Handles swaps, liquidity provision, fees
Similar to Uniswap V2 Pair
6. Router Contract
Handles complex trades across multiple pairs
Provides optimal swap paths
Manages slippage protection
User-friendly interface for DEX interactions
Graduation Flow:
Bonding Curve Phase: Token trades on curve until threshold (e.g., 4pETH market cap)
Migration Trigger: Curve contract automatically creates DEX pair
Liquidity Transfer: All pETH reserves + remaining tokens move to DEX pair
LP Token Handling: it burn LP tokens  for permanent liquidity, automatically 
Trading Switch: Token becomes freely tradeable on the DEX
Key Benefits of This Approach:
Complete Ecosystem: Your launchpad bootstraps the entire DeFi trading infrastructure
Permanent Liquidity: Graduated tokens have guaranteed liquidity forever
Platform Control: You control the entire trading experience from launch to maturity
First Mover Advantage: Become the primary DEX on the chain
This makes your launchpad much more valuable since you're not just a token creator - you're building the foundational trading infrastructure for the entire chain. Users will naturally return to trade graduated tokens, creating a flywheel effect.
5% fee on every buys and 1% fee on every sells and 4% fee for every launch 
1B total supply of every ERC20


Note, the native token of the chain is pETH



# Complete DEX Launchpad Smart Contract Development Request

You are a senior Solidity developer tasked with creating a complete, production-ready DEX launchpad ecosystem for a chain using pETH as the native token. This system must be 100% deployable without errors and follow the highest security and gas optimization standards.

## CRITICAL REQUIREMENTS

### Technical Specifications
- **Solidity Version**: 0.8.19 or higher
- **Native Token**: pETH (not ETH)
- **Token Standard**: ERC-20 with 1B total supply for all launched tokens
- **Fee Structure**: 
  - 5% fee on buys
  - 1% fee on sells  
  - 4% launch fee
- **Graduation Threshold**: 4 pETH market cap
- **Security Level**: Production-grade with comprehensive access controls
- **Gas Optimization**: Implement all standard optimizations

### Architecture Requirements

Create the following contracts with full implementation:

#### 1. LaunchpadFactory.sol
```
- Deploys new token launches
- Stores global configuration (fees, thresholds)
- Tracks all launched tokens and their status
- Owner-only configuration updates
- Emergency pause functionality
- Fee collection and withdrawal
```

#### 2. BondingCurve.sol (Template contract)
```
- Mathematical bonding curve for price discovery
- Handles buy/sell transactions with pETH
- Manages token supply and pETH reserves
- Implements 5% buy fee and 1% sell fee
- Auto-triggers graduation at 4 pETH market cap
- Migrates all liquidity to DEX pair upon graduation
- Slippage protection
```

#### 3. LaunchToken.sol (ERC-20 Template)
```
- Standard ERC-20 with 1B total supply
- Initially restricted trading (only bonding curve)
- Unrestricted transfers after graduation
- Ownership transfer to graduated DEX pair
- Metadata management
```

#### 4. DEXFactory.sol
```
- Creates new pETH/Token pairs for graduated tokens
- Tracks all created pairs
- Fee recipient management
- Pair code hash for CREATE2 deployments
```

#### 5. DEXPair.sol
```
- Constant product AMM (x * y = k)
- Handles swaps with 0.3% fee
- Liquidity provision and removal
- Price oracle functionality
- Flash loan protection
- MEV resistance measures
```

#### 6. DEXRouter.sol
```
- Multi-hop swap routing
- Slippage protection
- Deadline enforcement
- Optimal path calculation
- User-friendly swap interface
- Liquidity management functions
```

#### 7. PriceLibrary.sol
```
- Mathematical functions for bonding curve
- Price calculation utilities
- Safe math operations
- Gas-optimized calculations
```

## SECURITY REQUIREMENTS (MANDATORY)

### Access Control
- Implement OpenZeppelin's AccessControl or Ownable2Step
- Multi-signature support for critical functions
- Role-based permissions (ADMIN, OPERATOR, etc.)
- Emergency pause mechanisms

### Reentrancy Protection
- Use OpenZeppelin's ReentrancyGuard on all external functions
- Follow checks-effects-interactions pattern
- Mutex locks where necessary

### Input Validation
- Comprehensive parameter validation
- Zero address checks
- Overflow/underflow protection (Solidity 0.8+)
- Deadline and slippage validations

### Economic Security
- MEV protection mechanisms
- Flash loan attack prevention
- Price manipulation resistance
- Liquidity bootstrapping protection

## GAS OPTIMIZATION REQUIREMENTS

### Contract Design
- Use packed structs where possible
- Minimize storage operations
- Implement efficient loops
- Use events for off-chain data

### Function Optimization
- Cache storage reads
- Use unchecked blocks where safe
- Optimize function selectors
- Implement batch operations

## DEPLOYMENT REQUIREMENTS

### Migration Scripts
Create Hardhat deployment scripts that:
```
1. Deploy all contracts in correct order
2. Configure initial parameters
3. Set up access controls
4. Verify contracts on explorer
5. Initialize system state
6. Run comprehensive tests
```

### Configuration Management
```
- Upgradeable proxy patterns where needed
- Environment-specific configurations
- Multi-network deployment support
- Gas price optimization
```

### Testing Suite
```
- Unit tests for all functions
- Integration tests for complete flows
- Edge case testing
- Gas consumption analysis
- Security vulnerability tests
```

## DELIVERABLES REQUIRED

1. **Complete Contract Suite** (7 contracts with full implementation)
2. **Deployment Scripts** (Hardhat-based with network configs)
3. **Test Suite** (Comprehensive coverage >95%)
4. **Configuration Files** (Network settings, ABIs)
5. **Documentation** (Function descriptions, usage guides)
6. **Gas Optimization Report** (Estimated costs per operation)

## IMPLEMENTATION FLOW

### Phase 1: Token Launch
```solidity
// User pays 4% pETH fee on launch
// Factory deploys BondingCurve + LaunchToken
// Initial liquidity bootstrapping begins
// Trading restricted to bonding curve only
```

### Phase 2: Bonding Curve Trading
```solidity
// Buy: User sends pETH → receives tokens (5% fee)
// Sell: User sends tokens → receives pETH (1% fee)
// Price calculated via mathematical curve
// Graduation triggered at 4 pETH market cap
```

### Phase 3: DEX Migration
```solidity
// BondingCurve creates DEX pair automatically
// All pETH reserves + remaining tokens → DEX pair
// LP tokens burned for permanent liquidity
// Token becomes freely tradeable
// Unrestricted transfers enabled
```

## CODE QUALITY STANDARDS

- **Comments**: Comprehensive NatSpec documentation
- **Naming**: Clear, consistent naming conventions
- **Structure**: Logical contract organization
- **Imports**: Minimal, efficient imports
- **Events**: Comprehensive event logging
- **Errors**: Custom error messages with context

## FINAL CHECKLIST

Before delivery, ensure:
- [ ] All contracts compile without warnings
- [ ] Deployment scripts execute successfully
- [ ] Tests achieve >95% coverage
- [ ] Gas usage is optimized
- [ ] Security best practices implemented
- [ ] No hardcoded addresses or values
- [ ] Proper error handling throughout
- [ ] Complete documentation provided

## SUCCESS CRITERIA

The delivered code must:
1. Deploy successfully on first attempt
2. Pass all security audits
3. Achieve optimal gas usage
4. Handle all edge cases gracefully
5. Be production-ready without modifications

Generate the complete, professional-grade smart contract ecosystem with all requirements fulfilled. Focus on security, efficiency, and maintainability.