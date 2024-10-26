require("@nomicfoundation/hardhat-toolbox");
require('dotenv').config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.20",
      },
      {
        version: "0.8.15",
      },
      {
        version: "0.7.6",
      },
      {
        version: "0.7.9",
      },

    ],
  },
  settings: {
    optimizer: {
      enabled: true,  // Abilita l'ottimizzatore
      runs: 500,      // Numero di iterazioni dell'ottimizzatore
    },
  },
  networks:{
    hardhat:{
      forking:{
        url: `https://mainnet.infura.io/v3/${process.env.INFURA_API_KEY}`
      }
    }
  }
};

