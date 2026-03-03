// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title SimpleAMM
 * @dev A minimal Automated Market Maker implementing constant product formula (x * y = k)
 * Note: This is for educational purposes. Production AMMs require complex security measures.
 */
contract SimpleAMM is ReentrancyGuard {
    IERC20 public token0;
    IERC20 public token1;
    
    // Reserves of tokens in the pool
    uint256 public reserve0;
    uint256 public reserve1;
    
    // Total liquidity tokens supplied (representing share of the pool)
    uint256 public totalLiquidity;
    
    // Mapping to track liquidity provided by each address
    mapping(address => uint256) public liquidityBalance;

    // Events for tracking off-chain
    event Swap(address indexed user, uint256 amountIn, uint256 amountOut, address tokenIn);
    event LiquidityAdded(address indexed provider, uint256 amount0, uint256 amount1, uint256 liquidity);
    event LiquidityRemoved(address indexed provider, uint256 amount0, uint256 amount1, uint256 liquidity);

    constructor(address _token0, address _token1) {
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
    }

    /**
     * @dev Add liquidity to the pool
     * @param amount0 Amount of token0 to add
     * @param amount1 Amount of token1 to add
     * @return liquidity Amount of liquidity tokens minted
     */
    function addLiquidity(uint256 amount0, uint256 amount1) external nonReentrant returns (uint256 liquidity) {
        require(amount0 > 0 && amount1 > 0, "Amounts must be greater than 0");
        
        // Transfer tokens from user to this contract
        SafeERC20.safeTransfer(token0, address(this), amount0);
        SafeERC20.safeTransfer(token1, address(this), amount1);

        // Calculate liquidity to mint
        if (totalLiquidity == 0) {
            // Initial liquidity: sqrt(amount0 * amount1) to prevent price manipulation on first deposit
            liquidity = sqrt(amount0 * amount1);
        } else {
            // Proportional liquidity based on existing reserves
            uint256 liquidity0 = (amount0 * totalLiquidity) / reserve0;
            uint256 liquidity1 = (amount1 * totalLiquidity) / reserve1;
            liquidity = liquidity0 < liquidity1 ? liquidity0 : liquidity1;
        }

        require(liquidity > 0, "Insufficient liquidity minted");

        // Update state
        totalLiquidity += liquidity;
        liquidityBalance[msg.sender] += liquidity;
        reserve0 += amount0;
        reserve1 += amount1;

        emit LiquidityAdded(msg.sender, amount0, amount1, liquidity);
    }

    /**
     * @dev Swap tokens based on constant product formula
     * @param amountIn Amount of input token
     * @param tokenIn Address of input token
     * @return amountOut Amount of output token received
     */
    function swap(uint256 amountIn, address tokenIn) external nonReentrant returns (uint256 amountOut) {
        require(amountIn > 0, "Insufficient input amount");
        require(tokenIn == address(token0) || tokenIn == address(token1), "Invalid token");

        bool isToken0 = tokenIn == address(token0);
        (IERC20 inputToken, IERC20 outputToken, uint256 reserveIn, uint256 reserveOut) = 
            isToken0 
            ? (token0, token1, reserve0, reserve1) 
            : (token1, token0, reserve1, reserve0);

        // Transfer input token from user
        SafeERC20.safeTransferFrom(inputToken, msg.sender, address(this), amountIn);

        // Calculate output amount using constant product formula: 
        // (reserveIn + amountIn) * (reserveOut - amountOut) = reserveIn * reserveOut
        // We also deduct a 0.3% fee (standard AMM fee)
        uint256 amountInWithFee = amountIn * 997; 
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;
        
        amountOut = numerator / denominator;

        require(amountOut > 0, "Insufficient output amount");

        // Transfer output token to user
        SafeERC20.safeTransfer(outputToken, msg.sender, amountOut);

        // Update reserves
        if (isToken0) {
            reserve0 += amountIn;
            reserve1 -= amountOut;
        } else {
            reserve1 += amountIn;
            reserve0 -= amountOut;
        }

        emit Swap(msg.sender, amountIn, amountOut, tokenIn);
    }

    // Helper function for initial liquidity calculation
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        } else {
            z = 0;
        }
    }
    
    // Allow withdrawing liquidity (Simplified for brevity)
    function removeLiquidity(uint256 amount) external {
        require(liquidityBalance[msg.sender] >= amount, "Insufficient liquidity balance");
        
        uint256 amount0 = (amount * reserve0) / totalLiquidity;
        uint256 amount1 = (amount * reserve1) / totalLiquidity;

        liquidityBalance[msg.sender] -= amount;
        totalLiquidity -= amount;
        reserve0 -= amount0;
        reserve1 -= amount1;

        SafeERC20.safeTransfer(token0, msg.sender, amount0);
        SafeERC20.safeTransfer(token1, msg.sender, amount1);

        emit LiquidityRemoved(msg.sender, amount0, amount1, amount);
    }
}