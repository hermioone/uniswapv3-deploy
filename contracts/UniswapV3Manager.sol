// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./lib/LiquidityMath.sol";
import "./lib/TickMath.sol";
import "./lib/Path.sol";
import "./lib/PoolAddress.sol";

import "./interfaces/IUniswapV3MintCallback.sol";
import "./interfaces/IUniswapV3SwapCallback.sol";
import "./interfaces/IUniswapV3Manager.sol";
import "./interfaces/IUniswapV3Pool.sol";

import "./base/PoolInitializer.sol";

import "hardhat/console.sol";

contract UniswapV3Manager is IUniswapV3Manager, IUniswapV3MintCallback, IUniswapV3SwapCallback, PoolInitializer {
    
    using Path for bytes;

    error SlippageCheckFailed(uint256 amount0, uint256 amount1);
    error TooLittleReceived(uint256 amountOut);


    constructor(address _factory) PoolInitializer(_factory) {
    }

    function mint(MintParams calldata params)
        public
        returns (uint256 amount0, uint256 amount1)
    {
        console.log("Mint: tokenA: %s, tokenB: %s, tickSpacing: %s",
            params.tokenA, params.tokenB, params.tickSpacing);
        console.log("amount0Desired: %s, amount1Desired: %s", params.amount0Desired, params.amount1Desired);
        address poolAddress = PoolAddress.computeAddress(factory, params.tokenA, params.tokenB, params.tickSpacing);
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);

        (uint160 sqrtPriceX96, int24 tick) = pool.slot0();
        uint160 sqrtPriceLowerX96 = TickMath.getSqrtRatioAtTick(params.lowerTick);
        uint160 sqrtPriceUpperX96 = TickMath.getSqrtRatioAtTick(params.upperTick);
        
        console.log("sqrtPriceX96: %s; sqrtPriceLowerX96: %s; sqrtPriceUpperX96: %s",
            sqrtPriceX96, sqrtPriceLowerX96, sqrtPriceUpperX96);
        console.logInt(tick);
        console.logInt(params.lowerTick);
        console.logInt(params.upperTick);

        uint128 liquidity = LiquidityMath.getLiquidityForAmounts(
            sqrtPriceX96,
            sqrtPriceLowerX96,
            sqrtPriceUpperX96,
            params.amount0Desired,
            params.amount1Desired
        );

        (amount0, amount1) = pool.mint(
            msg.sender,
            params.lowerTick,
            params.upperTick,
            liquidity,
            abi.encode(
                IUniswapV3Pool.CallbackData({
                    token0: pool.token0(),
                    token1: pool.token1(),
                    payer: msg.sender
                })
            )
        );

        if (amount0 < params.amount0Min || amount1 < params.amount1Min) {
            console.log("amount0: %s, amount0Min: %s", amount0, params.amount0Min);
            console.log("amount1: %s, amount1Min: %s", amount1, params.amount1Min);
            revert SlippageCheckFailed(amount0, amount1);
        }
    }

    function swapSingle(SwapSingleParams calldata params)
        public
        returns (uint256 amountOut)
    {
        amountOut = _swap(
            params.amountIn,
            msg.sender,
            params.sqrtPriceLimitX96,
            SwapCallbackData({
                path: abi.encodePacked(
                    params.tokenIn,
                    params.tickSpacing,
                    params.tokenOut
                ),
                payer: msg.sender
            })
        );
    }

    function swap(SwapParams memory params) public returns (uint256 amountOut) {
        address payer = msg.sender;
        bool hasMultiplePools;

        while (true) {
            hasMultiplePools = params.path.hasMultiplePools();

            params.amountIn = _swap(
                params.amountIn,
                hasMultiplePools ? address(this) : params.recipient,
                0,
                SwapCallbackData({path: params.path.getFirstPool(), payer: payer})
            );

            if (hasMultiplePools) {
                payer = address(this);
                params.path = params.path.skipToken();
            } else {
                amountOut = params.amountIn;
                break;
            }
        }

        if (amountOut < params.minAmountOut)
            revert TooLittleReceived(amountOut);
    }

    function _swap(
        uint256 amountIn,
        address recipient,
        uint160 sqrtPriceLimitX96,
        SwapCallbackData memory data
    ) internal returns (uint256 amountOut) {
        (address tokenIn, address tokenOut, uint24 tickSpacing) = data
            .path
            .decodeFirstPool();

        bool zeroForOne = tokenIn < tokenOut;
        IUniswapV3Pool pool = getPool(tokenIn, tokenOut, tickSpacing);
        (int256 amount0, int256 amount1) = pool.swap(
                recipient,
                zeroForOne,
                amountIn,
                sqrtPriceLimitX96 == 0
                    ? (
                        zeroForOne
                            ? TickMath.MIN_SQRT_RATIO + 1
                            : TickMath.MAX_SQRT_RATIO - 1
                    )
                    : sqrtPriceLimitX96,
                abi.encode(data)
            );

        amountOut = uint256(-(zeroForOne ? amount1 : amount0));
    }

    function getPool(address token0, address token1, uint24 tickSpacing) internal view returns (IUniswapV3Pool pool) {
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);
        pool = IUniswapV3Pool(PoolAddress.computeAddress(factory, token0, token1, tickSpacing));
    }

    function uniswapV3MintCallback(uint256 amount0, uint256 amount1, bytes calldata data) override external {
        IUniswapV3Pool.CallbackData memory extra = abi.decode(data, (IUniswapV3Pool.CallbackData));

        // 增加流动性的回调，所以 amount0 和 amount1 都是 > 0
        IERC20(extra.token0).transferFrom(extra.payer, msg.sender, amount0);
        IERC20(extra.token1).transferFrom(extra.payer, msg.sender, amount1);
    }

    function uniswapV3SwapCallback(int256 amount0, int256 amount1, bytes calldata data_) override external {
        SwapCallbackData memory data = abi.decode(data_, (SwapCallbackData));
        (address tokenIn, address tokenOut, ) = data.path.decodeFirstPool();

        bool zeroForOne = tokenIn < tokenOut;

        int256 amount = zeroForOne ? amount0 : amount1;

        if (data.payer == address(this)) {
            IERC20(tokenIn).transfer(msg.sender, uint256(amount));
        } else {
            IERC20(tokenIn).transferFrom(data.payer, msg.sender, uint256(amount));
        }
    }
}