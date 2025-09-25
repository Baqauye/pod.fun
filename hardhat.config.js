require('dotenv').config();

const { deployer_private_key: PRIVATE_KEY, peth_rpc_url: RPC_URL } = process.env;

module.exports = {
  solidity: {
    version: '0.8.19',
    settings: {
      optimizer: {
        enabled: true,
        runs: 800
      }
    }
  },
  networks: {
    peth: {
      url: RPC_URL || 'http://localhost:8545',
      accounts: PRIVATE_KEY ? [PRIVATE_KEY] : []
    }
  }
};
