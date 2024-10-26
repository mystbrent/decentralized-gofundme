require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.19",
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
    }
  }
};