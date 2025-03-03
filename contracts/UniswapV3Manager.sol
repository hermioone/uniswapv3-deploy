// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./UniswapV3Pool.sol";
import "./interfaces/IUniswapV3MintCallback.sol";
import "./interfaces/IUniswapV3SwapCallback.sol";

contract UniswapV3Manager is IUniswapV3MintCallback, IUniswapV3SwapCallback {
    
    function mint(
        address poolAddress_, 
        int24 lowerTick, 
        int24 upperTick, 
        uint128 liquidity, 
        bytes calldata data
    ) public {
        UniswapV3Pool(poolAddress_).mint(
            msg.sender,
            lowerTick,
            upperTick,
            liquidity,
            data
        );
    }

    function swap(
        address poolAddress_,
        bytes calldata data
    ) public {
        UniswapV3Pool(poolAddress_).swap(msg.sender, data);
    }

    function uniswapV3MintCallback(uint256 amount0, uint256 amount1, bytes calldata data) override external {
        UniswapV3Pool.CallbackData memory extra = abi.decode(data, (UniswapV3Pool.CallbackData));

        // 增加流动性的回调，所以 amount0 和 amount1 都是 > 0
        IERC20(extra.token0).transferFrom(extra.payer, msg.sender, amount0);
        IERC20(extra.token1).transferFrom(extra.payer, msg.sender, amount1);
    }

    function uniswapV3SwapCallback(int256 amount0, int256 amount1, bytes calldata data) override external {
        UniswapV3Pool.CallbackData memory extra = abi.decode(data, (UniswapV3Pool.CallbackData));

        // 交易的回调函数，所以 amount0 > 0 时 amount1 < 0，或者 amount0 < 0 时 amount1 > 0
        if (amount0 > 0) {
            // 意味着需要调用者转账 amount0 的 token0 给 uniswapv3
            IERC20(extra.token0).transferFrom(extra.payer, msg.sender, uint256(amount0));
        }
        if (amount1 > 0) {
            IERC20(extra.token1).transferFrom(extra.payer, msg.sender, uint256(amount1));
        }
    }
}