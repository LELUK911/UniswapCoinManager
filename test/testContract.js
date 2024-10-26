const { ethers } = require("hardhat");

// Descrizione del test suite per il contratto UniswapAndCoinManager
describe("UniswapAndCoinManager", function () {
  let uniswapAndCoinManager, owner, syntraCoin, uniswapPoolPriceGetter, swapRouter, syntraAddress, WETH9
  const wethMainnetAddress = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"; // Indirizzo WETH per mainnet

  // Configurazione iniziale che viene eseguita prima di ogni test
  beforeEach(async function () {
    
    [owner] = await ethers.getSigners() // Ottiene il firmatario principale (owner)
    WETH9 = await ethers.getContractAt("IWETH9", wethMainnetAddress, owner); // Collega il contratto WETH
    const amountToWrap = ethers.parseEther("100");
    await WETH9.deposit({ value: amountToWrap }); // Converte 100 Ether in WETH

    // Esegue il deployment del contratto UniswapAndCoinManager
    const UniswapAndCoinManager = await ethers.getContractFactory('UniswapAndCoinManager0')
    uniswapAndCoinManager = await UniswapAndCoinManager.deploy()
    await uniswapAndCoinManager.waitForDeployment()

    // Esegue il deployment del contratto SyntraCoin con 40 milioni di token iniziali
    const SyntraCoin = await ethers.getContractFactory('SyntraCoin')
    syntraCoin = await SyntraCoin.deploy(owner.address, ethers.parseEther('40000000'))
    await syntraCoin.waitForDeployment()
    await syntraCoin.connect(owner).transfer(await uniswapAndCoinManager.getAddress(), ethers.parseEther('40000000')) // Trasferisce i token al contratto UniswapAndCoinManager
    syntraAddress = await syntraCoin.getAddress() // Ottiene l'indirizzo di SyntraCoin


    // Esegue il deployment del contratto UniswapPoolPriceGetter
    const UniswapPoolPriceGetter = await ethers.getContractFactory('UniswapPoolPriceGetter')
    uniswapPoolPriceGetter = await UniswapPoolPriceGetter.deploy()
    await uniswapPoolPriceGetter.waitForDeployment()

    // Collega il contratto SwapRouter di Uniswap
    swapRouter = await ethers.getContractAt("ISwapRouter", "0xE592427A0AEce92De3Edee1F18E0157C05861564");
  });

  // Testa il deploy del token e la funzionalità di swap
  it('Test deploy Token and swap', async () => {
    const etherForDeploy = "100"
    await uniswapAndCoinManager.connect(owner).deployCoinAndPool(ethers.parseEther(etherForDeploy), syntraAddress, { value: ethers.parseEther(etherForDeploy), gasLimit: 10000000 }) // Esegue il deploy della pool con Ether

    const poolAddress = await uniswapAndCoinManager.connect(owner).getAddressPool() // Ottiene l'indirizzo della pool
    await uniswapPoolPriceGetter.setUniswapPool(poolAddress); // Imposta l'indirizzo della pool in UniswapPoolPriceGetter

    let price = await uniswapPoolPriceGetter.calcEffectivePrice() // Calcola il prezzo effettivo di SyntraCoin
    let [sqrtPrice, tick] = await uniswapPoolPriceGetter.getPoolPrice() // Ottiene i dati di prezzo e tick della pool
    console.log("Data at pool Creation")
    console.log(`Syntr's price -> ${price.toString()}`)
    console.log(`Actual Tick -> ${tick.toString()}`)

    // Definisce la funzione di swap per i token
    const swapFunctio = async (tokenIn, TokenOut, amount) => {
      const swapParams = {
        tokenIn: tokenIn, // Indirizzo del token di input (es. SyntraCoin)
        tokenOut: TokenOut,       // Indirizzo del token di output (es. WETH)
        fee: 3000,                              // Commissione della pool (0,3%)
        recipient: owner.address,                // Destinatario dello swap
        deadline: Math.floor(Date.now() / 1000) + 60 * 10, // Scadenza dell'operazione (10 minuti da ora)
        amountIn: amount,                   // Quantità di token in input da scambiare
        amountOutMinimum: 0,                    // Quantità minima di token in output (qui impostata a 0 per i test)
        sqrtPriceLimitX96: 0                    // Limite di prezzo (qui impostato a 0, senza limiti)
      };
      try {
        await swapRouter.connect(owner).exactInputSingle(swapParams, {
          gasLimit: 2000000, // Limite di gas elevato per sicurezza
        });
      } catch (error) {
        console.error("Swap failed:", error);
      }
    }

    // Mint di SyntraCoin per il test e approvazione dell'importo da scambiare
    await syntraCoin.connect(owner).mint(owner.address, ethers.parseEther('10000000'));
    await syntraCoin.connect(owner).approve(await swapRouter.getAddress(), ethers.parseEther('10000000'));


    const amountToWrap = ethers.parseEther("500");
    await WETH9.deposit({ value: amountToWrap }); // Wrappa 500 Ether in WETH
    await WETH9.approve(await swapRouter.getAddress(), amountToWrap);   // Approva l'importo WETH per lo swap

    // Definisce i vari casi di test per lo swap di SyntraCoin e WETH
    const swapTestCases = [
      { tokenIn: syntraAddress, tokenOut: wethMainnetAddress, swapAmount: ethers.parseEther('50') },
      { tokenIn: wethMainnetAddress, tokenOut: syntraAddress, swapAmount: ethers.parseEther('0.02') },  // $50 in WETH
      { tokenIn: syntraAddress, tokenOut: wethMainnetAddress, swapAmount: ethers.parseEther('75') },
      { tokenIn: wethMainnetAddress, tokenOut: syntraAddress, swapAmount: ethers.parseEther('0.03') },  // $75 in WETH
      { tokenIn: syntraAddress, tokenOut: wethMainnetAddress, swapAmount: ethers.parseEther('100') },
      { tokenIn: wethMainnetAddress, tokenOut: syntraAddress, swapAmount: ethers.parseEther('0.04') },  // $100 in WETH
      { tokenIn: syntraAddress, tokenOut: wethMainnetAddress, swapAmount: ethers.parseEther('150') },
      { tokenIn: wethMainnetAddress, tokenOut: syntraAddress, swapAmount: ethers.parseEther('0.06') },  // $150 in WETH
      { tokenIn: syntraAddress, tokenOut: wethMainnetAddress, swapAmount: ethers.parseEther('200') },
      { tokenIn: wethMainnetAddress, tokenOut: syntraAddress, swapAmount: ethers.parseEther('0.08') },  // $200 in WETH
      { tokenIn: syntraAddress, tokenOut: wethMainnetAddress, swapAmount: ethers.parseEther('300') },
      { tokenIn: wethMainnetAddress, tokenOut: syntraAddress, swapAmount: ethers.parseEther('0.12') },  // $300 in WETH
      { tokenIn: syntraAddress, tokenOut: wethMainnetAddress, swapAmount: ethers.parseEther('400') },
      { tokenIn: wethMainnetAddress, tokenOut: syntraAddress, swapAmount: ethers.parseEther('0.16') },  // $400 in WETH
      { tokenIn: syntraAddress, tokenOut: wethMainnetAddress, swapAmount: ethers.parseEther('500') },
      { tokenIn: wethMainnetAddress, tokenOut: syntraAddress, swapAmount: ethers.parseEther('0.20') },  // $500 in WETH
      { tokenIn: syntraAddress, tokenOut: wethMainnetAddress, swapAmount: ethers.parseEther('600') },
      { tokenIn: wethMainnetAddress, tokenOut: syntraAddress, swapAmount: ethers.parseEther('0.24') },  // $600 in WETH
      { tokenIn: syntraAddress, tokenOut: wethMainnetAddress, swapAmount: ethers.parseEther('700') },
      { tokenIn: wethMainnetAddress, tokenOut: syntraAddress, swapAmount: ethers.parseEther('0.28') },  // $700 in WETH
      { tokenIn: syntraAddress, tokenOut: wethMainnetAddress, swapAmount: ethers.parseEther('800') },
      { tokenIn: wethMainnetAddress, tokenOut: syntraAddress, swapAmount: ethers.parseEther('0.32') },  // $800 in WETH
      { tokenIn: syntraAddress, tokenOut: wethMainnetAddress, swapAmount: ethers.parseEther('900') },
      { tokenIn: wethMainnetAddress, tokenOut: syntraAddress, swapAmount: ethers.parseEther('0.36') },  // $900 in WETH
      { tokenIn: syntraAddress, tokenOut: wethMainnetAddress, swapAmount: ethers.parseEther('1000') },
      { tokenIn: wethMainnetAddress, tokenOut: syntraAddress, swapAmount: ethers.parseEther('0.40') },  // $1000 in WETH
      { tokenIn: syntraAddress, tokenOut: wethMainnetAddress, swapAmount: ethers.parseEther('1200') },
      { tokenIn: wethMainnetAddress, tokenOut: syntraAddress, swapAmount: ethers.parseEther('0.48') },  // $1200 in WETH
      { tokenIn: syntraAddress, tokenOut: wethMainnetAddress, swapAmount: ethers.parseEther('1400') },
      { tokenIn: wethMainnetAddress, tokenOut: syntraAddress, swapAmount: ethers.parseEther('0.56') },  // $1400 in WETH
      { tokenIn: syntraAddress, tokenOut: wethMainnetAddress, swapAmount: ethers.parseEther('1600') },
      { tokenIn: wethMainnetAddress, tokenOut: syntraAddress, swapAmount: ethers.parseEther('0.64') },  // $1600 in WETH
      { tokenIn: syntraAddress, tokenOut: wethMainnetAddress, swapAmount: ethers.parseEther('1800') },
      { tokenIn: wethMainnetAddress, tokenOut: syntraAddress, swapAmount: ethers.parseEther('0.72') },  // $1800 in WETH
      { tokenIn: syntraAddress, tokenOut: wethMainnetAddress, swapAmount: ethers.parseEther('2000') },
      { tokenIn: wethMainnetAddress, tokenOut: syntraAddress, swapAmount: ethers.parseEther('0.80') },  // $2000 in WETH
      { tokenIn: syntraAddress, tokenOut: wethMainnetAddress, swapAmount: ethers.parseEther('2200') },
      { tokenIn: wethMainnetAddress, tokenOut: syntraAddress, swapAmount: ethers.parseEther('0.88') },  // $2200 in WETH
      { tokenIn: syntraAddress, tokenOut: wethMainnetAddress, swapAmount: ethers.parseEther('2400') },
      { tokenIn: wethMainnetAddress, tokenOut: syntraAddress, swapAmount: ethers.parseEther('0.96') },  // $2400 in WETH
      { tokenIn: syntraAddress, tokenOut: wethMainnetAddress, swapAmount: ethers.parseEther('2600') },
      { tokenIn: wethMainnetAddress, tokenOut: syntraAddress, swapAmount: ethers.parseEther('1.04') },  // $2600 in WETH
      { tokenIn: syntraAddress, tokenOut: wethMainnetAddress, swapAmount: ethers.parseEther('2800') },
      { tokenIn: wethMainnetAddress, tokenOut: syntraAddress, swapAmount: ethers.parseEther('1.12') },  // $2800 in WETH
      { tokenIn: syntraAddress, tokenOut: wethMainnetAddress, swapAmount: ethers.parseEther('3000') },
      { tokenIn: wethMainnetAddress, tokenOut: syntraAddress, swapAmount: ethers.parseEther('1.20') },  // $3000 in WETH
      { tokenIn: syntraAddress, tokenOut: wethMainnetAddress, swapAmount: ethers.parseEther('3200') },
      { tokenIn: wethMainnetAddress, tokenOut: syntraAddress, swapAmount: ethers.parseEther('1.28') }   // $3200 in WETH
    ];

    // Esegue i casi di test definiti per la funzione di swap
    for (let i = 0; i < swapTestCases.length; i++) {
      await swapFunctio(swapTestCases[i].tokenIn, swapTestCases[i].tokenOut, swapTestCases[i].swapAmount);

      // Calcola il prezzo effettivo dopo ogni swap
      price = await uniswapPoolPriceGetter.calcEffectivePrice()
      let [sqrtPrice, tick] = await uniswapPoolPriceGetter.getPoolPrice()

      console.log(`Swap Operation -> ${i}`)
      if (swapTestCases[i].tokenIn == syntraAddress) {
        console.log(`Sell operation   -> amount : ${swapTestCases[i].swapAmount}`)
      } else {
        console.log(`Buy operation   -> amount : ${swapTestCases[i].swapAmount}`)
      }
      console.log(`Price token -> ${price.toString()}`)
      console.log(`Actual Tick -> ${tick.toString()}`)
    }

  });
});


