require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.22",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  networks: {
    tenderly: {
      url: process.env.TENDERLY_FORK_URL,
      accounts: [process.env.PRIVATE_KEY]
    },
    hardhat: {
      forking: {
        url: process.env.TENDERLY_FORK_URL,
        blockNumber: 17500000
      }
    },
    buildbear: {
      url: process.env.BUILDBEAR_FORK_URL,
      accounts: [process.env.PRIVATE_KEY],
      
      // httpHeaders: {
      //   'keep-alive': 'true'
      // },
      // // Dynamic gas settings
      // gasPrice: {
      //   maxFeePerGas: 'auto',
      //   maxPriorityFeePerGas: 'auto',
      //   type: 2  // EIP-1559 style transactions
      // },
      // // Connection settings
      // connectionTimeout: 300000,
      // // Optional: Configure HTTP client
      // client: {
      //   keepalive: true,
      //   keepaliveInterval: 60000, // 60 seconds
      //   maxSockets: 20
      // }
      

    }
  }
};