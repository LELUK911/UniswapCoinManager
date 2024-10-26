/**
 * @dev The `UniswapAndCoinManager` contract is designed to manage the deployment and liquidity provisioning of a custom ERC20 token
 * on Uniswap V3, as well as facilitate token minting and swaps for participants. This contract plays a critical role in the 
 * lifecycle of the SyntraCoin, ensuring that liquidity is properly established on Uniswap and that participants can trade their tokens.
 *
 * **Key Features:**
 * 
 * 1. **Token Deployment and Management:**
 *    - The contract deploys a custom ERC20 token (SyntraCoin) with a fixed initial supply of 40 million tokens.
 *    - It stores the address of the deployed SyntraCoin contract, allowing it to interact with and manage the token.
 *    - After deployment, the contract can transfer ownership of the SyntraCoin contract to the owner of this contract, ensuring centralized control over the token's governance.
 *
 * 2. **Liquidity Pool Creation on Uniswap V3:**
 *    - The contract creates a Uniswap V3 pool for the SyntraCoin and WETH pair, allowing for liquidity provision and token trading.
 *    - It calculates the initial price of the pool using Chainlink's ETH/USD price feed, ensuring an accurate and up-to-date market price.
 *    - The pool is funded with a predefined amount of SyntraCoin and ETH, and liquidity is added to the pool within a specific price range defined by ticks.
 *    - The contract uses the Uniswap V3 libraries (TickMath, FullMath, and LiquidityAmounts) to handle complex calculations related to price and liquidity.
 *
 * 3. **Token Minting and Distribution:**
 *    - The contract allows the presale contract to mint SyntraCoins for participants based on their presale contributions.
 *    - This function is restricted to the presale contract, ensuring that only authorized entities can mint new tokens.
 *
 * 4. **Token Swaps and Liquidity Management:**
 *    - Participants can use this contract to swap their SyntraCoins for WETH through the Uniswap V3 pool.
 *    - The contract facilitates the swap by approving the transfer of SyntraCoins to the Uniswap V3 SwapRouter and executing the swap.
 *    - It ensures that participants receive WETH in exchange for their SyntraCoins, with the swap parameters configured for optimal execution.
 *
 * 5. **Ownership and Control (OnlyOwner Functions):**
 *    - The contract includes functions restricted to the owner, such as setting the presale contract address and transferring SyntraCoin ownership.
 *    - The owner is responsible for managing critical aspects of the token and liquidity, including setting up the pool and ensuring liquidity is added.
 *    - The `onlyOwner` modifier ensures that sensitive operations are controlled by a single authorized entity, maintaining the integrity and security of the contract.
 *
 * 6. **Callback Functions for Uniswap V3:**
 *    - The contract implements the `IUniswapV3MintCallback` and `IUniswapV3SwapCallback` interfaces, allowing it to interact with the Uniswap V3 protocol.
 *    - During liquidity minting, the `uniswapV3MintCallback` function ensures that the owed tokens are transferred to the pool.
 *    - During swaps, the `uniswapV3SwapCallback` function handles the transfer of tokens to the pool based on the swap's parameters.
 *
 * 7. **Price Feed Integration:**
 *    - The contract integrates with Chainlink's ETH/USD price feed to obtain the latest market price of ETH.
 *    - This price is used to calculate the initial price ratio for the Uniswap V3 pool, ensuring that the pool is initialized with an accurate market price.
 *
 * The `UniswapAndCoinManager` contract is a crucial component of the SyntraCoin ecosystem, providing the necessary infrastructure for token deployment,
 * liquidity provisioning, and token trading on Uniswap V3. It combines the functionality of token management with the decentralized liquidity features of Uniswap,
 * ensuring that SyntraCoin can be traded efficiently and securely.
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;
// Importa Uniswap V3 Core
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import "@uniswap/v3-core/contracts/libraries/FixedPoint96.sol";
import "@uniswap/v3-core/contracts/interfaces/pool/IUniswapV3PoolActions.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";

// Importa Uniswap V3 Periphery
import "@uniswap/v3-periphery/contracts/interfaces/external/IWETH9.sol";
import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

// Importa OpenZeppelin SafeERC20 e IERC20
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Importa Chainlink AggregatorV3
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

// Importa il contratto custom SyntraCoin (devi sistemare il percorso di questo contratto)
import "./SyntraCoin.sol";
import "hardhat/console.sol";
/// @custom:security-contact admin@syntralink.net

interface ISyntraCoin {
    function mint(address to, uint256 amount) external;
    function approve(address spender, uint256 amount) external returns (bool);
}

contract UniswapAndCoinManager0 is Ownable, IUniswapV3MintCallback, IUniswapV3SwapCallback {
    using SafeERC20 for IERC20;

    constructor() Ownable(msg.sender) {}

    IUniswapV3Factory public uniswapFactory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984); // @dev Address of the Uniswap V3 Factory contract on Ethereum mainnet
    IWETH9 public weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // @dev Address of the WETH9 contract on Ethereum mainnet
    AggregatorV3Interface internal priceFeed = AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419); // @dev Address of the Chainlink ETH/USD Price Feed contract on Ethereum mainnet
    ISwapRouter public swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564); // @dev Address of the Uniswap V3 SwapRouter contract on Ethereum mainnet
    address public coinAddress; // @dev State variable to store the address of the SyntraCoin token
    address public presaleContractAddress; // @dev State variable to store the address of the presale contract
    uint256 public constant TOKEN_AMOUNT_FOR_LIQUIDITY = 40e6 * DECIMALS; // @dev Constant for the amount of tokens allocated for liquidity (40 million tokens)
    uint256 public constant DECIMALS = 1e18; // @dev Constant for the number of decimal places (18 decimals)
    uint256 public constant PRICE_TOKEN0 = 25 * 1e16; // @dev Constant for the initial price of token0 in the Uniswap pool (0.25 ETH)
    uint24 public constant FEE = 3000; // @dev Constant for the Uniswap pool fee (0.3%)
    int24 public constant TICK_LOWER = -150000; // @dev Constant for the lower tick of the liquidity range
    int24 public constant TICK_UPPER = 150000; // @dev Constant for the upper tick of the liquidity range
    address public uniswapPool; // @dev State variable to store the address of the created Uniswap pool
    event CoinDeployed(address indexed coinAddress, uint256 indexed mintedBalance); // @dev Event emitted when the SyntraCoin token is deployed
    event PoolCreated(address indexed pool, uint256 indexed amount1, uint256 indexed amount2); // @dev Event emitted when the Uniswap pool is created

    /**
     * @notice Sets the presale contract address. Can only be called by the owner.
     * @param contractAddress The address of the presale contract
     * @dev This function allows the owner to link the presale contract to this contract,
     * enabling authorized interactions between the two contracts.
     */
    function setPresaleContractAddress(address contractAddress) external onlyOwner {
        require(contractAddress != address(0), "Invalid address"); // @dev Ensure the provided address is not the zero address
        presaleContractAddress = contractAddress; // @dev Set the presale contract address
    }

    /**
     * @notice Deploys the custom ERC20 token and creates a Uniswap V3 pool with initial liquidity.
     * @param ethForPool The amount of ETH to be used as liquidity in the Uniswap pool
     * @dev This function is restricted to be called only by the presale contract. It deploys
     * the SyntraCoin token and sets up the liquidity pool on Uniswap V3.
     */
    function deployCoinAndPool(
        uint256 ethForPool,
        address coin
    ) external payable {
        //require(msg.sender == presaleContractAddress, "Caller is not the presale contract"); // @dev Ensure the caller is the presale contract
        //_deployCoin(); // @dev Call the internal function to deploy the SyntraCoin token
        coinAddress = coin;
        _createAndFundUniswapPool(ethForPool); // @dev Call the internal function to create and fund the Uniswap pool
    }

    /**
     * @notice Mints SyntraCoins for a participant. Can only be called by the presale contract.
     * @param participant The address of the participant to receive the minted tokens
     * @param amount The amount of SyntraCoins to mint
     * @dev This function mints tokens for presale participants based on their contributions,
     * ensuring the correct distribution of SyntraCoins.
     */
    function mintTokens(address participant, uint256 amount) external {
        require(msg.sender == presaleContractAddress, "Caller is not the presale contract"); // @dev Ensure the caller is the presale contract
        require(coinAddress != address(0), "Coin not deployed yet"); // @dev Ensure the SyntraCoin token is deployed
        SyntraCoin(coinAddress).mint(participant, amount); // @dev Mint the specified amount of SyntraCoins to the participant's address
    }

    /**
     * @notice Internal function to deploy the SyntraCoin token.
     * @dev This function is called during the initial setup of the contract.
     * It deploys the SyntraCoin contract and stores its address for future interactions.
     */
    function _deployCoin() internal {
        SyntraCoin coin = new SyntraCoin(address(this), TOKEN_AMOUNT_FOR_LIQUIDITY); // @dev Deploy a new SyntraCoin contract with the specified token amount
        coinAddress = address(coin); // @dev Store the address of the deployed SyntraCoin contract
        emit CoinDeployed(coinAddress, coinAddress.balance); // @dev Emit an event to log the deployment of the SyntraCoin contract
    }

    /**
     * @notice Transfers the ownership of the SyntraCoin contract to the owner of the UniswapAndCoinManager contract.
     * @dev This function can only be called by the owner of the UniswapAndCoinManager contract.
     * It transfers control of the SyntraCoin contract to the contract owner.
     */
    function transferCoinOwnership() external onlyOwner {
        require(coinAddress != address(0), "Coin not deployed yet"); // @dev Ensure the SyntraCoin token is deployed
        SyntraCoin(coinAddress).transferOwnership(owner()); // @dev Transfer the ownership of the SyntraCoin contract to the owner of this contract
        emit OwnershipTransferred(msg.sender, owner()); // @dev Optionally emit an event to log the ownership transfer
    }

    /**
     * @notice Internal function to create and fund a Uniswap V3 pool with initial liquidity.
     * @param ethForPool The amount of ETH to provide as liquidity
     * @dev This function sets up the liquidity pool for SyntraCoin on Uniswap V3,
     * initializing it with a calculated price and adding both ETH and SyntraCoins as liquidity.
     */
    function _createAndFundUniswapPool(uint256 ethForPool) internal {
        //uint160 sqrtPriceX96 = _calculateSqrtPriceX96(); // @dev Calculate the initial price in square root format
        
        //CORREZZIONE
        uint160 sqrtPriceX96 = _calculateSqrtPriceX96(
            ethForPool,
            TOKEN_AMOUNT_FOR_LIQUIDITY
        );
        //
        address pool = _createUniswapPool(sqrtPriceX96, ethForPool); // @dev Create the Uniswap V3 pool
        //CORREZZIONE
        //_fundUniswapPool(pool, ethForPool, TOKEN_AMOUNT_FOR_LIQUIDITY, sqrtPriceX96); // @dev Add liquidity to the Uniswap V3 pool
        _fundUniswapPool(pool,TOKEN_AMOUNT_FOR_LIQUIDITY,ethForPool, sqrtPriceX96); // @dev Add liquidity to the Uniswap V3 pool

    }

    /**
     * @notice Internal function to calculate the square root of the price ratio in X96 format.
     * @return sqrtPriceX96 The initial price of the Uniswap pool in square root format
     * @dev This function calculates the square root of the price ratio, which is required for initializing the Uniswap pool.
     */
    function _calculateSqrtPriceX96(
        uint _amount0,//correzzione  ->ether nella pool
        uint _amount1 //correzzione  -> Syntra nella pool
        ) internal view returns (uint160 sqrtPriceX96) {
        // inutile con la nuova logica
        //uint256 priceToken1 = _getLatestETHUSDPrice() * DECIMALS; // @dev Fetch the latest ETH price in wei from the Chainlink price feed
        //
        
        // logica errata
        //uint256 ratioX96 = FullMath.mulDiv(PRICE_TOKEN0, FixedPoint96.Q96, priceToken1); // @dev Calculate the price ratio in X96 format
        
        //CORREZZIONE
        uint256 ratioX96 = FullMath.mulDiv(
            _amount1, //Syntra
            FixedPoint96.Q96,
            _amount0 //ether
        );
        
        sqrtPriceX96 = uint160(_sqrt(ratioX96) * 2 ** 48); // @dev Convert the price ratio to square root format
    }

    /**
     * @notice Internal function to create a Uniswap V3 pool.
     * @param sqrtPriceX96 The initial price of the pool in square root format
     * @param ethForPool The amount of ETH to provide as liquidity
     * @return pool The address of the created Uniswap V3 pool
     * @dev This function creates a new Uniswap V3 pool for SyntraCoin and WETH, initializes it with the provided price,
     * and approves the necessary tokens for liquidity provision.
     */
    function _createUniswapPool(uint160 sqrtPriceX96, uint256 ethForPool) internal returns (address pool) {
        address token1 = address(coinAddress); // @dev Define the address of SyntraCoin as token0
        address token0 = address(weth); // @dev Define the address of WETH as token1
        pool = uniswapFactory.createPool(token0, token1, FEE); // @dev Create a new Uniswap V3 pool
        require(pool != address(0), "Pool creation failed"); // @dev Ensure the pool creation was successful
        IERC20(coinAddress).safeIncreaseAllowance(pool, TOKEN_AMOUNT_FOR_LIQUIDITY); // @dev Approve the SyntraCoin tokens for the Uniswap pool
        weth.deposit{value: ethForPool}(); // @dev Convert the provided ETH to WETH
        IERC20(address(weth)).safeIncreaseAllowance(pool, ethForPool); // @dev Approve the WETH tokens for the Uniswap pool
        IUniswapV3Pool(pool).initialize(sqrtPriceX96); // @dev Initialize the Uniswap pool with the calculated price
        uniswapPool = pool; // @dev Store the address of the created Uniswap pool
    }

    /**
     * @notice Internal function to add liquidity to a Uniswap V3 pool.
     * @param pool The address of the Uniswap V3 pool
     * @param ethForLiquidity The amount of ETH to provide as liquidity
     * @param tokenAmountForLiquidity The amount of tokens to provide as liquidity
     * @param sqrtPriceX96 The initial price of the pool in square root format
     * @dev This function adds the specified amounts of ETH and SyntraCoins to the created Uniswap V3 pool,
     * within the defined price range.
     */
    function _fundUniswapPool(address pool, uint256 tokenAmountForLiquidity,uint256 ethForLiquidity,  uint160 sqrtPriceX96) internal {
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(TICK_LOWER),
            TickMath.getSqrtRatioAtTick(TICK_UPPER),
            ethForLiquidity,
            tokenAmountForLiquidity
        ); // @dev Calculate the liquidity amount to be added to the pool
        bytes memory data = abi.encode(address(this)); // @dev Encode the callback data
        //IERC20(coinAddress).safeIncreaseAllowance(address(this), tokenAmountForLiquidity); // @dev Approve SyntraCoin tokens for the contract
        //IERC20(address(weth)).safeIncreaseAllowance(address(this), ethForLiquidity); // @dev Approve WETH tokens for the contract
        try IUniswapV3PoolActions(pool).mint(
            address(this),
            TICK_LOWER,
            TICK_UPPER,
            liquidity,
            data
        ) returns (uint256 amount0, uint256 amount1) {
            emit PoolCreated(pool, amount0, amount1); // @dev Emit an event to log the pool creation
        } catch (bytes memory reason) {
            revert(string(reason)); // @dev Revert with the caught error message if the minting fails
        }
    }

    /**
     * @notice Public function to get the address of the created Uniswap pool.
     * @return The address of the Uniswap pool
     * @dev This function returns the address of the Uniswap pool created by this contract,
     * allowing external contracts and users to interact with the pool.
     */
    function getUniswapPool() external view returns (address) {
        require(uniswapPool != address(0), "Uniswap pool has not been created yet"); // @dev Ensure the Uniswap pool has been created
        return uniswapPool; // @dev Return the address of the Uniswap pool
    }

    /**
     * @notice Uniswap V3 Mint Callback function.
     * @dev This function is called by the Uniswap V3 pool during minting to collect the owed amounts.
     * It transfers the owed amounts of token0 (SyntraCoin) and token1 (WETH) to the pool.
     * @param amount0Owed The amount of token0 owed to the pool
     * @param amount1Owed The amount of token1 owed to the pool
     * @param data Additional data passed to the callback
     */
    function uniswapV3MintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata data) external override {
        address pool = msg.sender; // @dev Get the address of the Uniswap pool that called the callback
        require(pool != address(0), "Invalid pool address"); // @dev Ensure the pool address is valid
        address sender = abi.decode(data, (address)); // @dev Decode the callback data to get the sender's address
        if (amount0Owed > 0) {
            require(weth.balanceOf(address(this)) >= amount0Owed, "Insufficient WETH in balance"); // @dev Ensure the contract has enough WETH balance
            IERC20(address(weth)).safeTransferFrom(address(this), pool, amount0Owed); // @dev Transfer the owed WETH tokens to the Uniswap pool
        
        }
        if (amount1Owed > 0) {
            // CORREZZIONE - safeTransferFrom genera un errore con la pool.
            //IERC20(coinAddress).safeTransferFrom(address(this), pool, amount1Owed); // @dev Transfer the owed SyntraCoin tokens to the Uniswap pool
            // Safe trasfert esegue correttamente il trasferimento
            IERC20(coinAddress).safeTransfer(msg.sender, amount1Owed); // @dev Transfer the owed SyntraCoin tokens to the Uniswap pool

        }
    }

    /**
     * @notice Internal function to calculate the square root of a given value.
     * @param y The value to calculate the square root of
     * @return z The calculated square root
     * @dev This function uses the Babylonian method to calculate the square root of the provided value.
     */
    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y; // @dev Initialize z with the value of y
            uint256 x = y / 2 + 1; // @dev Initialize x with half of y plus 1
            while (x < z) {
                z = x; // @dev Update z with the value of x
                x = (y / x + x) / 2; // @dev Update x with the average of y/x and x
            }
        } else if (y != 0) {
            z = 1; // @dev Set z to 1 if y is not zero
        }
    }

    /**
     * @notice Fetches the latest ETH/USD price from the Chainlink price feed.
     * @return The latest ETH price in USD with 18 decimals
     * @dev This function retrieves the latest ETH price from the Chainlink price feed,
     * which is used for price calculations in the Uniswap pool.
     */
    function _getLatestETHUSDPrice() public view returns (uint256) {
        (, int256 answer, , , ) = priceFeed.latestRoundData(); // @dev Fetch the latest price data from the Chainlink price feed
        return uint256(answer / 1e8); // @dev Convert the Chainlink price to an 18-decimal value
    }

    /**
     * @notice Uniswap V3 Swap Callback function.
     * @dev This function is called by the Uniswap V3 pool during a swap to handle the token transfers.
     * It transfers the owed amounts of token0 (SyntraCoin) and token1 (WETH) to the pool based on the swap parameters.
     * @param amount0Delta The amount of token0 transferred during the swap
     * @param amount1Delta The amount of token1 transferred during the swap
     * @param data Additional data passed to the callback
     */
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external override {
        require(msg.sender == uniswapPool, "Callback called from unauthorized address"); // @dev Ensure the callback is called by the Uniswap pool
        if (amount0Delta > 0) {
            IERC20(coinAddress).safeTransfer(msg.sender, uint256(amount0Delta)); // @dev Transfer the owed SyntraCoin tokens to the Uniswap pool
        }
        if (amount1Delta > 0) {
            IERC20(address(weth)).safeTransfer(msg.sender, uint256(amount1Delta)); // @dev Transfer the owed WETH tokens to the Uniswap pool
        }
    }



    //FUNZIONE DI DEBUG:
        function getAddressPool() public view returns (address poolAddress) {
        poolAddress = uniswapPool;
        return poolAddress;
    }
}
