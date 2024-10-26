// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import "hardhat/console.sol";

contract UniswapPoolPriceGetter {
    address public uniswapPool; // @dev Variabile che memorizza l'indirizzo della pool Uniswap V3

    constructor() {}

    /**
     * @notice Imposta l'indirizzo della pool Uniswap V3.
     * @param _uniswapPool L'indirizzo della pool Uniswap da monitorare per ottenere il prezzo
     * @dev Questa funzione consente di specificare la pool da cui verranno recuperate le informazioni sul prezzo.
     */
    function setUniswapPool(address _uniswapPool) public {
        uniswapPool = _uniswapPool; // @dev Assegna l'indirizzo della pool alla variabile di stato
    }

    /**
     * @notice Ottiene il prezzo della pool Uniswap V3 sotto forma di prezzo radice e tick.
     * @return sqrtPriceX96 Il prezzo radice della pool (in formato X96)
     * @return tick Il valore del tick attuale nella pool
     * @dev Recupera i dati dello slot0 della pool, che include il prezzo radice e il tick. Richiede che l'indirizzo della pool sia impostato.
     */
    function getPoolPrice()
        public
        view
        returns (uint160 sqrtPriceX96, int24 tick)
    {
        require(uniswapPool != address(0), "Pool not exist"); // @dev Verifica che la pool esista

        IUniswapV3Pool pool = IUniswapV3Pool(uniswapPool); // @dev Crea un'istanza della pool

        (sqrtPriceX96, tick, , , , , ) = pool.slot0(); // @dev Ottiene il prezzo radice e il tick corrente dalla pool

        return (sqrtPriceX96, tick); // @dev Restituisce il prezzo radice e il tick della pool
    }

    /**
     * @notice Calcola il prezzo effettivo della pool Uniswap V3.
     * @return price Il prezzo calcolato della pool
     * @dev La funzione utilizza il prezzo radice per calcolare il prezzo effettivo, evitando overflow grazie alla libreria FullMath.
     */
    function calcEffectivePrice() public view returns (uint256 price) {
        (uint160 sqrtPrice, ) = getPoolPrice(); // @dev Ottiene il prezzo radice corrente della pool
        uint256 priceSqrt = uint256(sqrtPrice); // @dev Converte il prezzo radice in uint256

        // Calcolo del prezzo utilizzando FullMath per evitare overflow
        price = FullMath.mulDiv(priceSqrt, priceSqrt, 1 << 192); // @dev Calcola il prezzo effettivo con una precisione X96

        return price; // @dev Restituisce il prezzo effettivo della pool
    }
}
