// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

// Import Uniswap V3 Core interfaces and libraries
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import "@uniswap/v3-core/contracts/libraries/FixedPoint96.sol";
import "@uniswap/v3-core/contracts/interfaces/pool/IUniswapV3PoolActions.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";

// Import Uniswap V3 Periphery interfaces and libraries
import "@uniswap/v3-periphery/contracts/interfaces/external/IWETH9.sol";
import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

// Import OpenZeppelin SafeERC20 and IERC20
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';


// Custom security contact for contract deployment
/// @custom:security-contact admin@customproject.net

// Define an interface for a generic custom ERC20 token
interface ICustomToken {
    function mint(address to, uint256 amount) external;
    function approve(address spender, uint256 amount) external returns (bool);
}

contract UniswapAndTokenManager is
    Ownable,
    IUniswapV3MintCallback,
    IUniswapV3SwapCallback
{
    using SafeERC20 for IERC20;

    // Constructor initializes the owner
    constructor() Ownable(msg.sender) {}

    // Uniswap-related state variables
    IUniswapV3Factory public uniswapFactory =
        IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984); // Address of the Uniswap V3 Factory on Ethereum mainnet
    IWETH9 public weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // Address of the WETH9 contract on Ethereum mainnet
    ISwapRouter public swapRouter =
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564); // Address of the Uniswap V3 SwapRouter on Ethereum mainnet

    // Token and pool management state variables
    address public tokenAddress; // Address of the custom ERC20 token
    uint256 public constant DECIMALS = 1e18; // Number of decimal places (18 decimals)
    uint24 public constant FEE = 3000; // Uniswap pool fee (0.3%)
    int24 public constant TICK_LOWER = -150000; // Lower tick for liquidity range
    int24 public constant TICK_UPPER = 150000; // Upper tick for liquidity range
    address public uniswapPool; // Address of the created Uniswap pool

    // Events for logging contract actions
    event TokenDeployed(address indexed tokenAddress, uint256 indexed mintedBalance);
    event PoolCreated(address indexed pool, uint256 indexed amount1, uint256 indexed amount2);

    /**
     * @notice Sets the address of the custom ERC20 token.
     * @param _tokenAddress The address of the token to be set.
     * @dev Only the contract owner can call this function.
     */
    function setTokenAddress(address _tokenAddress) external onlyOwner {
        require(_tokenAddress != address(0), "Token address cannot be zero");
        tokenAddress = _tokenAddress;
    }

    /**
     * @notice Creates and funds a new Uniswap V3 pool for the token and WETH.
     * @param ethForPool Amount of ETH to provide as liquidity.
     * @param tokenForPool Amount of tokens to provide as liquidity.
     * @dev Transfers the specified token amount to the contract and initializes the pool.
     */
    function createNewPool(uint ethForPool, uint tokenForPool) external payable onlyOwner {
        IERC20(tokenAddress).safeTransferFrom(msg.sender, address(this), tokenForPool);
        _createAndFundUniswapPool(ethForPool, tokenForPool);
    }

    /**
     * @notice Internal function to create and fund a Uniswap V3 pool with initial liquidity.
     * @param ethForPool Amount of ETH to provide as liquidity.
     * @param tokenForPool Amount of tokens to provide as liquidity.
     * @dev Calculates the initial price and sets up the liquidity pool.
     */
    function _createAndFundUniswapPool(uint256 ethForPool, uint tokenForPool) internal {
        uint160 sqrtPriceX96 = _calculateSqrtPriceX96(ethForPool, tokenForPool);
        address pool = _createUniswapPool(sqrtPriceX96, ethForPool,tokenForPool);
        _fundUniswapPool(pool, tokenForPool, ethForPool, sqrtPriceX96);
    }

    /**
     * @notice Internal function to calculate the square root of the price ratio in X96 format.
     * @param _amount0 Amount of token0 (ETH) provided as liquidity.
     * @param _amount1 Amount of token1 (custom token) provided as liquidity.
     * @return sqrtPriceX96 The calculated square root price in X96 format.
     */
    function _calculateSqrtPriceX96(uint _amount0, uint _amount1) internal pure returns (uint160 sqrtPriceX96) {
        uint256 ratioX96 = FullMath.mulDiv(_amount1, FixedPoint96.Q96, _amount0);
        sqrtPriceX96 = uint160(_sqrt(ratioX96) * 2 ** 48);
    }

    /**
     * @notice Internal function to create a Uniswap V3 pool.
     * @param sqrtPriceX96 The initial price of the pool in square root format.
     * @param ethForPool Amount of ETH to provide as liquidity.
     * @return pool Address of the created Uniswap V3 pool.
     */
    function _createUniswapPool(uint160 sqrtPriceX96, uint256 ethForPool,uint tokenForPool) internal returns (address pool) {
        address token1 = address(tokenAddress);
        address token0 = address(weth);
        pool = uniswapFactory.createPool(token0, token1, FEE);
        require(pool != address(0), "Pool creation failed");
        IERC20(tokenAddress).safeIncreaseAllowance(pool, tokenForPool);
        weth.deposit{value: ethForPool}();
        IERC20(address(weth)).safeIncreaseAllowance(pool, ethForPool);
        IUniswapV3Pool(pool).initialize(sqrtPriceX96);
        uniswapPool = pool;
    }


        /**
     * @notice Internal function to add liquidity to a Uniswap V3 pool.
     * @param pool The address of the Uniswap V3 pool.
     * @param ethForLiquidity Amount of ETH to provide as liquidity.
     * @param tokenAmountForLiquidity Amount of tokens to provide as liquidity.
     * @param sqrtPriceX96 The initial price of the pool in square root format.
     * @dev Adds the specified amounts of ETH and custom tokens to the Uniswap V3 pool.
     */
    function _fundUniswapPool(
        address pool,
        uint256 tokenAmountForLiquidity,
        uint256 ethForLiquidity,
        uint160 sqrtPriceX96
    ) internal {
        // Calculate the liquidity amount based on the given parameters
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(TICK_LOWER),
            TickMath.getSqrtRatioAtTick(TICK_UPPER),
            ethForLiquidity,
            tokenAmountForLiquidity
        );

        // Callback data
        bytes memory data = abi.encode(address(this));

        // Try adding liquidity to the pool
        try
            IUniswapV3PoolActions(pool).mint(
                address(this),
                TICK_LOWER,
                TICK_UPPER,
                liquidity,
                data
            )
        returns (uint256 amount0, uint256 amount1) {
            emit PoolCreated(pool, amount0, amount1);
        } catch (bytes memory reason) {
            revert(string(reason));
        }
    }

    /**
     * @notice Internal function to calculate the square root of a given value.
     * @param y The value to calculate the square root of.
     * @return z The calculated square root.
     * @dev This function uses the Babylonian method to calculate the square root.
     */
    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y; // Start with the input value
            uint256 x = y / 2 + 1; // Initial guess for x
            while (x < z) {
                z = x; // Update z with the current guess
                x = (y / x + x) / 2; // Average the guess
            }
        } else if (y != 0) {
            z = 1; // For small numbers, the square root is 1
        }
    }


       /**
     * @notice Uniswap V3 Mint Callback function.
     * @dev This function is called by the Uniswap V3 pool during minting to collect the owed amounts.
     * It transfers the owed amounts of token0 (CustomToken) and token1 (WETH) to the pool.
     * @param amount0Owed The amount of token0 owed to the pool.
     * @param amount1Owed The amount of token1 owed to the pool.
     * @param data Additional data passed to the callback.
     */
    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external override {
        address pool = msg.sender; // Get the address of the Uniswap pool that called the callback
        require(pool == uniswapPool, "Invalid pool address"); // Ensure the callback is from the correct pool

        if (amount0Owed > 0) {
            // Transfer the owed WETH to the pool
            IERC20(address(weth)).safeTransfer(pool, amount0Owed);
        }
        if (amount1Owed > 0) {
            // Transfer the owed CustomToken to the pool
            IERC20(tokenAddress).safeTransfer(pool, amount1Owed);
        }
    }

    /**
     * @notice Uniswap V3 Swap Callback function.
     * @dev This function is called by the Uniswap V3 pool during a swap to handle the token transfers.
     * @param amount0Delta The amount of token0 transferred during the swap.
     * @param amount1Delta The amount of token1 transferred during the swap.
     * @param data Additional data passed to the callback.
     */
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external override {
        require(msg.sender == uniswapPool, "Unauthorized callback");

        if (amount0Delta > 0) {
            // Transfer the owed WETH to the pool
            IERC20(address(weth)).safeTransfer(msg.sender, uint256(amount0Delta));
        }
        if (amount1Delta > 0) {
            // Transfer the owed CustomToken to the pool
            IERC20(tokenAddress).safeTransfer(msg.sender, uint256(amount1Delta));
        }
    }

}
