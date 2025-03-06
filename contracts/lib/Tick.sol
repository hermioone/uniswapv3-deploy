// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./LiquidityMath.sol";

library Tick {
    struct Info {
        bool initialized;
        // total liquidity at tick
        // 这个 tick 的总的 liquidity
        uint128 liquidityGross;
        // amount of liqudiity added or subtracted when tick is crossed
        // 从左到右跨过这个 tick 是 liquidity 的增量，
        int128 liquidityNet;
    }

    /// @param upper 是否是区间的上边界
    function update(
        mapping(int24 => Tick.Info) storage self,
        int24 tick,
        int128 liquidityDelta,
        bool upper
    ) internal returns (bool flipped) {
        Tick.Info storage tickInfo = self[tick];
        uint128 liquidityBefore = tickInfo.liquidityGross;
        uint128 liquidityAfter = LiquidityMath.addLiquidity(liquidityBefore, liquidityDelta);

        flipped = (liquidityAfter == 0) != (liquidityBefore == 0);

        if (liquidityBefore == 0) {
            tickInfo.initialized = true;
        }

        tickInfo.liquidityGross = liquidityAfter;
        // 如果这个 tick 是区间的上边界，那么 从左到右 跨越这个 tick 时应该 - liquidityDelta
        // 如果是下边界，那么 从左到右 跨越这个 tick 时应该 + liquidityDelta
        tickInfo.liquidityNet = upper
            ? int128(int256(tickInfo.liquidityNet) - liquidityDelta)
            : int128(int256(tickInfo.liquidityNet) + liquidityDelta);
    }

    function cross(mapping(int24 => Tick.Info) storage self, int24 tick)
        internal
        view
        returns (int128 liquidityDelta)
    {
        Tick.Info storage info = self[tick];
        liquidityDelta = info.liquidityNet;
    }
}