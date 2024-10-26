const { ethers } = require("hardhat");

async function main() {
    
    // Esegue il deployment del contratto UniswapAndCoinManager
    const UniswapAndCoinManager = await ethers.getContractFactory('UniswapAndCoinManager0')
    const uniswapAndCoinManager = await UniswapAndCoinManager.deploy()
    await uniswapAndCoinManager.waitForDeployment()
}

main()
    .then(() => { process.exit(0) })
    .catch((e) => {
        console.error(e)
        process.exit(1)
    })