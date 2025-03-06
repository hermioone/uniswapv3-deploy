// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./Math.sol";

library SwapMath {
    function computeSwapStep(
        uint160 sqrtPriceCurrentX96,
        uint160 sqrtPriceTargetX96,
        uint128 liquidity,
        uint256 amountRemaining
    )
        internal
        pure
        returns (uint160 sqrtPriceNextX96, uint256 amountIn, uint256 amountOut)
    {
        bool zeroForOne = sqrtPriceCurrentX96 >= sqrtPriceTargetX96;

        amountIn = zeroForOne
            ? Math.calcAmount0Delta(
                sqrtPriceCurrentX96,
                sqrtPriceTargetX96,
                liquidity
            )
            : Math.calcAmount1Delta(
                sqrtPriceCurrentX96,
                sqrtPriceTargetX96,
                liquidity
            );

        if (amountRemaining >= amountIn) {
            // 此时说明当前 tick 区间不足以满足所有的交易金额，
            sqrtPriceNextX96 = sqrtPriceTargetX96;
        } else {
            // 此时说明当前 tick 区间足以满足交易金额
            // sqrtPriceCurrentX96 < sqrtPriceNextX96 < sqrtPriceTargetX96
            sqrtPriceNextX96 = Math.getNextSqrtPriceFromInput(
                sqrtPriceCurrentX96,
                liquidity,
                amountRemaining,
                zeroForOne
            );
        }

        amountIn = Math.calcAmount0Delta(
            sqrtPriceCurrentX96,
            sqrtPriceNextX96,
            liquidity
        );
        amountOut = Math.calcAmount1Delta(
            sqrtPriceCurrentX96,
            sqrtPriceNextX96,
            liquidity
        );

        if (!zeroForOne) {
            (amountIn, amountOut) = (amountOut, amountIn);
        }
    }
}
