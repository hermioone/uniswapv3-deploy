// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../interfaces/IUniswapV3Factory.sol";
import "../interfaces/IUniswapV3Pool.sol";

import "hardhat/console.sol";

abstract contract PoolInitializer {

    address public immutable factory;

    constructor(address _factory) {
        factory = _factory;
    }

    function createAndInitializePoolIfNecessary(
        address token0,
        address token1,
        uint24 tickSpacing,
        uint160 sqrtPriceX96
    ) external payable returns (address pool) {
        require(token0 < token1);
        pool = IUniswapV3Factory(factory).getPool(token0, token1, tickSpacing);

        if (pool == address(0)) {
            console.log("Deploy Pool...%s, %s, %s", token0, token1, tickSpacing);
            console.log("sqrtPriceX96: %s", sqrtPriceX96);
            pool = IUniswapV3Factory(factory).createPool(token0, token1, tickSpacing);
            console.log("Pool address: %s", pool);
            IUniswapV3Pool(pool).initialize(sqrtPriceX96);
        } else {
            (uint160 sqrtPriceX96Existing, ) = IUniswapV3Pool(pool).slot0();
            if (sqrtPriceX96Existing == 0) {
                IUniswapV3Pool(pool).initialize(sqrtPriceX96);
            }
        }
    }
}