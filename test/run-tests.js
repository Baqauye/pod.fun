const fs = require('fs');
const path = require('path');
const assert = require('assert');

function fileContains(file, pattern) {
  const content = fs.readFileSync(file, 'utf8');
  return pattern.test(content);
}

function expectContains(file, pattern, message) {
  if (!fileContains(file, pattern)) {
    throw new Error(`Assertion failed for ${file}: ${message}`);
  }
}

const contractsDir = path.join(__dirname, '..', 'contracts');
const requiredContracts = [
  'core/LaunchpadFactory.sol',
  'core/BondingCurve.sol',
  'core/LaunchToken.sol',
  'core/ProtocolTreasury.sol',
  'dex/DEXFactory.sol',
  'dex/DEXPair.sol',
  'dex/DEXRouter.sol'
];

for (const relPath of requiredContracts) {
  const absPath = path.join(contractsDir, relPath);
  assert.ok(fs.existsSync(absPath), `Missing contract ${relPath}`);
}

expectContains(
  path.join(contractsDir, 'core', 'BondingCurve.sol'),
  /BUY_FEE_BPS = 500/,
  'BondingCurve buy fee must be 5%'
);

expectContains(
  path.join(contractsDir, 'core', 'BondingCurve.sol'),
  /SELL_FEE_BPS = 100/,
  'BondingCurve sell fee must be 1%'
);

expectContains(
  path.join(contractsDir, 'core', 'LaunchpadFactory.sol'),
  /launchFeeBps = 400/,
  'Launch fee must be 4%'
);

expectContains(
  path.join(contractsDir, 'core', 'LaunchToken.sol'),
  /INITIAL_SUPPLY = 1_000_000_000 \* 1e18/,
  'Launch token supply must be 1B tokens'
);

console.log('Static configuration tests passed.');
