// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./lib/Position.sol";
import "./lib/Tick.sol";
import "./lib/TickBitMap.sol";
import "./lib/Math.sol";
import "./lib/TickMath.sol";
import "./lib/SwapMath.sol";
import "./lib/LiquidityMath.sol";

import "./interfaces/IUniswapV3MintCallback.sol";
import "./interfaces/IUniswapV3SwapCallback.sol";
import "./interfaces/IUniswapV3Pool.sol";
import "./interfaces/IUniswapV3PoolDeployer.sol";

contract UniswapV3Pool is IUniswapV3Pool {
    error InvalidTickRange();
    error ZeroLiquidity();
    error InsufficientInputAmount();
    error NotEnoughLiquidity();
    error InvalidPriceLimit();
    error AlreadyInitialized();

    event Mint(
        address sender,
        address indexed owner,
        int24 indexed tickLower,
        int24 indexed tickUpper,
        uint128 amount,
        uint256 amount0,
        uint256 amount1
    );
    event Swap(
        address indexed sender,
        address indexed recipient,
        int256 amount0,
        int256 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick
    );

    event Log(uint256 amount0, uint256 amount1);

    using Tick for mapping(int24 => Tick.Info);
    using TickBitmap for mapping(int16 => uint256);
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;

    int24 internal constant MIN_TICK = -887272;
    int24 internal constant MAX_TICK = -MIN_TICK;

    address public immutable factory;
    address public immutable token0;
    address public immutable token1;
    uint24 public immutable tickSpacing;

    // 当前 swap 的状态
    struct SwapState {
        // 待交换的 tokenIn 的金额
        uint256 amountSpecifiedRemaining;
        // 已交换的 tokenOut 的金额
        uint256 amountCalculated;
        // 当前 swap 交易结束后的价格
        uint160 sqrtPriceX96;
        // 当前 swap 交易结束后的 tick
        int24 tick;
        uint128 liquidity;
    }

    // 维护当前交易”一步“的状态
    struct StepState {
        // 循环开始时的价格
        uint160 sqrtPriceStartX96;
        // 能够为交易提供流动性的下一个已初始化的tick
        int24 nextTick;
        // 下一个 tick 的价格
        uint160 sqrtPriceNextX96;
        // amountIn 和 amountOut 是当前循环中流动性能够提供的数量
        uint256 amountIn;
        uint256 amountOut;
        bool initialized;
    }

    struct Slot0 {
        // 当前价格
        uint160 sqrtPriceX96;
        // 当前 tick
        int24 tick;
    }
    Slot0 public slot0;

    // 总的流动性
    uint128 public liquidity;

    mapping(int24 => Tick.Info) public ticks;
    // tick 的位图，tick是 int24（24bit的int），tick的前16位是 key，用于从 map 中找到对应的 value（位图）
    // tick的后8位是位图的key，2 ** 8 的范围为 [0, 255]，表示 value 中哪一个位
    mapping(int16 => uint256) public tickBitmap;
    mapping(bytes32 => Position.Info) positions;

    constructor() {
        (factory, token0, token1, tickSpacing) = IUniswapV3PoolDeployer(msg.sender).parameters();
    }

    function initialize(uint160 sqrtPriceX96) public {
        if (slot0.sqrtPriceX96 != 0) {
            revert AlreadyInitialized();
        }

        int24 tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
        slot0 = Slot0({sqrtPriceX96: sqrtPriceX96, tick: tick});
    }

    // 提供流动性
    function mint(
        address owner,
        int24 lowerTick,
        int24 upperTick,
        uint128 amount,
        bytes calldata data
    ) external override returns (uint256 amount0, uint256 amount1) {
        if (lowerTick >= upperTick || lowerTick < TickMath.MIN_TICK || upperTick > TickMath.MAX_TICK) {
            revert InvalidTickRange();
        } 
        if (amount <= 0) {
            revert ZeroLiquidity();
        }

        bool flippedLower = ticks.update(lowerTick, int128(amount), false);
        bool flippedUpper = ticks.update(upperTick, int128(amount), true);


        if (flippedLower) {
            tickBitmap.flipTick(lowerTick, 1);
        }

        if (flippedUpper) {
            tickBitmap.flipTick(upperTick, 1);
        }

        Position.Info storage position = positions.get(owner, lowerTick, upperTick);
        position.update(amount);

        Slot0 memory slot0_ = slot0;

        if (slot0_.tick < lowerTick) {
            // 价格区间在当前 tick 右边，此时提供的流动性应全部由 token0 提供
            amount0 = Math.calcAmount0Delta(
                TickMath.getSqrtRatioAtTick(lowerTick),
                TickMath.getSqrtRatioAtTick(upperTick),
                amount
            );
        } else if (slot0_.tick < upperTick) {
            // 价格区间包含当前 tick
            amount0 = Math.calcAmount0Delta(
                slot0_.sqrtPriceX96,
                TickMath.getSqrtRatioAtTick(upperTick),
                amount
            );

            amount1 = Math.calcAmount1Delta(
                slot0_.sqrtPriceX96,
                TickMath.getSqrtRatioAtTick(lowerTick),
                amount
            );

            liquidity = LiquidityMath.addLiquidity(liquidity, int128(amount));
        } else {
            // 价格区间在当前 tick 左边，此时提供的流动性应全部由 token1 提供
            amount1 = Math.calcAmount1Delta(
                TickMath.getSqrtRatioAtTick(lowerTick),
                TickMath.getSqrtRatioAtTick(upperTick),
                amount
            );
        }

        uint256 balance0Before;
        uint256 balance1Before;
        if (amount0 > 0) {
            balance0Before = balance0();
        }
        if (amount1 > 0) {
            balance1Before = balance1();
        }
        IUniswapV3MintCallback(msg.sender).uniswapV3MintCallback(amount0, amount1, data);
        if (amount0 > 0 && balance0Before + amount0 > balance0()) {
            revert InsufficientInputAmount();
        }
        if (amount1 > 0 && balance1Before + amount1 > balance1()) {
            revert InsufficientInputAmount();
        }
        emit Mint(msg.sender, owner, lowerTick, upperTick, amount, amount0, amount1);
    }

    /// @param zeroForOne 用来控制交易方向的 flag：当设置为 true，是用 token0 兑换 token1；false 则相反。例如，如果 token0 是ETH，token1 是USDC，将 zeroForOne 设置为 true 意味着用 ETH 购买 USDC
    /// @param amountSpecified 用户希望卖出的 token 数量
    /// @param sqrtPriceLimitX96 滑点保护，当 zeroForOne 为 true 时，交易的价格不能低于 sqrtPriceLimitX96；当 zeroForOne 为 false 时，交易的价格不能高于 sqrtPriceLimitX96
    function swap(
        address recipient,
        bool zeroForOne,
        uint256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external override returns (int256 amount0, int256 amount1) {
        // Caching for gas saving
        Slot0 memory slot0_ = slot0;
        uint128 liquidity_ = liquidity;

        if (zeroForOne
                ? sqrtPriceLimitX96 > slot0_.sqrtPriceX96 || sqrtPriceLimitX96 < TickMath.MIN_SQRT_RATIO
                : sqrtPriceLimitX96 < slot0_.sqrtPriceX96 || sqrtPriceLimitX96 > TickMath.MAX_SQRT_RATIO
        ) {
            revert InvalidPriceLimit();
        }

        SwapState memory state = SwapState({
            amountSpecifiedRemaining: amountSpecified,
            amountCalculated: 0,
            sqrtPriceX96: slot0_.sqrtPriceX96,
            tick: slot0_.tick,
            liquidity: liquidity_
        });

        while (
            state.amountSpecifiedRemaining > 0 &&
            state.sqrtPriceX96 != sqrtPriceLimitX96
        ) {
            StepState memory step;

            step.sqrtPriceStartX96 = state.sqrtPriceX96;

            (step.nextTick, step.initialized) = tickBitmap.nextInitializedTickWithinOneWord(
                state.tick,
                1,
                zeroForOne
            );
            step.sqrtPriceNextX96 = TickMath.getSqrtRatioAtTick(step.nextTick);

            (state.sqrtPriceX96, step.amountIn, step.amountOut) = SwapMath.computeSwapStep(
                    state.sqrtPriceX96,
                    (zeroForOne
                            ? step.sqrtPriceNextX96 < sqrtPriceLimitX96
                            : step.sqrtPriceNextX96 > sqrtPriceLimitX96
                    )
                        ? sqrtPriceLimitX96
                        : step.sqrtPriceNextX96,
                    state.liquidity,
                    state.amountSpecifiedRemaining
                );

            state.amountSpecifiedRemaining -= step.amountIn;
            state.amountCalculated += step.amountOut;

            if (state.sqrtPriceX96 == step.sqrtPriceNextX96) {
                if (step.initialized) {
                    int128 liquidityDelta = ticks.cross(step.nextTick);

                    // 当 zeroForOne 为 true，也就是从右往左略过 tick，
                    // liquidityDelta 表示从左到右略过 tick 是 liquidity 的变化量，所以应该取负
                    if (zeroForOne) {
                        liquidityDelta = -liquidityDelta;
                    }

                    state.liquidity = LiquidityMath.addLiquidity(state.liquidity, liquidityDelta);

                    if (state.liquidity == 0) {
                        revert NotEnoughLiquidity();
                    }
                }

                state.tick = zeroForOne ? step.nextTick - 1 : step.nextTick;
            } else if (state.sqrtPriceX96 != step.sqrtPriceStartX96) {
                state.tick = TickMath.getTickAtSqrtRatio(state.sqrtPriceX96);
            }
        }

        if (state.tick != slot0_.tick) {
            (slot0.sqrtPriceX96, slot0.tick) = (state.sqrtPriceX96, state.tick);
        }

        if (liquidity_ != state.liquidity) {
            liquidity = state.liquidity;
        }        

        (amount0, amount1) = zeroForOne
            ? (
                int256(amountSpecified - state.amountSpecifiedRemaining),
                -int256(state.amountCalculated)
            )
            : (
                -int256(state.amountCalculated),
                int256(amountSpecified - state.amountSpecifiedRemaining)
            );

        if (zeroForOne) {
            IERC20(token1).transfer(recipient, uint256(-amount1));

            uint256 balance0Before = balance0();
            IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(
                amount0,
                amount1,
                data
            );
            if (balance0Before + uint256(amount0) > balance0())
                revert InsufficientInputAmount();
        } else {
            IERC20(token0).transfer(recipient, uint256(-amount0));

            uint256 balance1Before = balance1();
            IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(
                amount0,
                amount1,
                data
            );
            if (balance1Before + uint256(amount1) > balance1())
                revert InsufficientInputAmount();
        }

        emit Swap(
            msg.sender,
            recipient,
            amount0,
            amount1,
            slot0.sqrtPriceX96,
            state.liquidity,
            slot0.tick
        );
    }

    function balance0() internal view returns (uint256) {
        return IERC20(token0).balanceOf(address(this));
    }

    function balance1() internal view returns (uint256) {
        return IERC20(token1).balanceOf(address(this));
    }
}
