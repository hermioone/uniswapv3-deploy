// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IUniswapV3Factory {

    function getPool(address tokenX, address tokenY, uint24 tickSpacing) external view returns (address pool);


    function createPool(address tokenX, address tokenY, uint24 tickSpacing) external returns (address pool);
}