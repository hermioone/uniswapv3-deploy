// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./lib/Position.sol";
import "./lib/Tick.sol";
import "./lib/TickBitMap.sol";
import "./lib/Math.sol";
import "./lib/TickMath.sol";
import "./lib/SwapMath.sol";

import "./interfaces/IUniswapV3MintCallback.sol";
import "./interfaces/IUniswapV3SwapCallback.sol";

contract UniswapV3Pool {
    error InvalidTickRange();
    error ZeroLiquidity();
    error InsufficientInputAmount(string tokenName, uint256 expected, uint256 actual);

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

    address public immutable token0;
    address public immutable token1;

    struct CallbackData {
        address token0;
        address token1;
        address payer;
    }

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

    constructor(
        address token0_,
        address token1_,
        uint160 sqrtPriceX96,
        int24 tick
    ) {
        token0 = token0_;
        token1 = token1_;

        slot0 = Slot0({sqrtPriceX96: sqrtPriceX96, tick: tick});
    }

    // 提供流动性
    function mint(
        address owner,
        int24 lowerTick,
        int24 upperTick,
        uint128 amount,
        bytes calldata data
    ) external returns (uint256 amount0, uint256 amount1) {
        emit Log(0, 0);
        if (lowerTick >= upperTick || lowerTick < MIN_TICK || upperTick > MAX_TICK) {
            revert InvalidTickRange();
        }
        if (amount <= 0) {
            revert ZeroLiquidity();
        }

        // 更新上下边界的 liquidity
        bool flippedLower = ticks.update(lowerTick, amount);
        bool flippedUpper = ticks.update(upperTick, amount);
        if (flippedLower) {
            tickBitmap.flipTick(lowerTick, 1);
        }

        if (flippedUpper) {
            tickBitmap.flipTick(upperTick, 1);
        }

        Position.Info storage position = positions.get(owner, lowerTick, upperTick);
        position.update(amount);

        // amount0 = 0.998976618347425280 ether;
        // amount1 = 5000 ether;

        amount0 = Math.calcAmount0Delta(
            TickMath.getSqrtRatioAtTick(slot0.tick),
            TickMath.getSqrtRatioAtTick(upperTick),
            amount
        );

        amount1 = Math.calcAmount1Delta(
            TickMath.getSqrtRatioAtTick(slot0.tick),
            TickMath.getSqrtRatioAtTick(lowerTick),
            amount
        );
        emit Log(amount0, amount1);

        liquidity += uint128(amount);

        // 调用回调函数转账，转账金额为 amount0 和 amount1
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
            revert InsufficientInputAmount("token0", amount0, (balance0() - balance0Before));
        }
        if (amount1 > 0 && balance1Before + amount1 > balance1()) {
            revert InsufficientInputAmount("token1", amount1, (balance1() - balance1Before));
        }
        emit Mint(msg.sender, owner, lowerTick, upperTick, amount, amount0, amount1);
    }

    /// @param zeroForOne 用来控制交易方向的 flag：当设置为 true，是用 token0 兑换 token1；false 则相反。例如，如果 token0 是ETH，token1 是USDC，将 zeroForOne 设置为 true 意味着用 ETH 购买 USDC
    /// @param amountSpecified 用户希望卖出的 token 数量
    function swap(
        address recipient,
        bool zeroForOne,
        uint256 amountSpecified,
        bytes calldata data
    ) public returns (int256 amount0, int256 amount1) {
        // TODO 需要把这些硬编码的替换为计算
        int24 nextTick = 85184;
        uint160 nextPrice = 5604469350942327889444743441197;
        amount0 = -0.008396714242162444 ether;
        amount1 = 42 ether;

        Slot0 memory slot0_ = slot0;
        SwapState memory state = SwapState({
            amountSpecifiedRemaining: amountSpecified,
            amountCalculated: 0,
            sqrtPriceX96: slot0_.sqrtPriceX96,
            tick: slot0_.tick
        });

        // TODO 在这个 while 循环中 liquidity 并没有发生改变，所以这里发生的交易还是局限在一个 tick 内的
        // 并没有跨 tick
        while (state.amountSpecifiedRemaining > 0) {
            StepState memory step;
            step.sqrtPriceStartX96 = state.sqrtPriceX96;
            (step.nextTick, ) = tickBitmap.nextInitializedTickWithinOneWord(
                state.tick,
                1,
                zeroForOne
            );
            // 计算
            step.sqrtPriceNextX96 = TickMath.getSqrtRatioAtTick(step.nextTick);

            (state.sqrtPriceX96, step.amountIn, step.amountOut) = SwapMath
                .computeSwapStep(
                    step.sqrtPriceStartX96,
                    step.sqrtPriceNextX96,
                    liquidity,
                    state.amountSpecifiedRemaining
                );

            state.amountSpecifiedRemaining -= step.amountIn;
            state.amountCalculated += step.amountOut;
            state.tick = TickMath.getTickAtSqrtRatio(state.sqrtPriceX96);
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
                revert InsufficientInputAmount("token0", uint256(amount0), (balance0() - balance0Before));
        } else {
            IERC20(token0).transfer(recipient, uint256(-amount0));

            uint256 balance1Before = balance1();
            IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(
                amount0,
                amount1,
                data
            );
            if (balance1Before + uint256(amount1) > balance1())
                revert InsufficientInputAmount("token1", uint256(amount1), (balance1() - balance1Before));
        }

        emit Swap(
            msg.sender,
            recipient,
            amount0,
            amount1,
            slot0.sqrtPriceX96,
            liquidity,
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
