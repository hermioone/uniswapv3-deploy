// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;


import "./interfaces/IUniswapV3PoolDeployer.sol";
import "./interfaces/IUniswapV3Factory.sol";
import "./UniswapV3Pool.sol";
import "hardhat/console.sol";

contract UniswapV3Factory is IUniswapV3PoolDeployer, IUniswapV3Factory {
    error PoolAlreadyExists();
    error ZeroAddressNotAllowed();
    error TokensMustBeDifferent();
    error UnsupportedTickSpacing();

    event PoolCreated(
        address indexed token0,
        address indexed token1,
        uint24 indexed tickSpacing,
        address pool
    );

    PoolParameters public parameters;

    mapping(uint24 => bool) public tickSpacings;
    mapping(address => mapping(address => mapping(uint24 => address))) public pools;

    constructor() {
        tickSpacings[10] = true;
        tickSpacings[60] = true;
    }

    function getPool(address tokenX, address tokenY, uint24 tickSpacing) public override view returns (address pool) {
        return pools[tokenX][tokenY][tickSpacing];
    }

    function createPool(address tokenX, address tokenY, uint24 tickSpacing) public override returns (address pool) {
        if (tokenX == tokenY) {
            revert TokensMustBeDifferent();
        }
        if (!tickSpacings[tickSpacing]) {
            revert UnsupportedTickSpacing();
        }

        (tokenX, tokenY) = tokenX < tokenY ? (tokenX, tokenY) : (tokenY, tokenX);
        console.log("tokenX: ", tokenX);
        console.log("tokenY: ", tokenY);

        if (tokenX == address(0)) {
            revert ZeroAddressNotAllowed();
        }
        if (pools[tokenX][tokenY][tickSpacing] != address(0)) {
            revert PoolAlreadyExists();
        }

        parameters = PoolParameters({
            factory: address(this),
            token0: tokenX,
            token1: tokenY,
            tickSpacing: tickSpacing
        });

        pool = address(
            new UniswapV3Pool{
                salt: keccak256(abi.encodePacked(tokenX, tokenY, tickSpacing))
            }()
        );

        delete parameters;

        pools[tokenX][tokenY][tickSpacing] = pool;
        pools[tokenY][tokenX][tickSpacing] = pool;

        emit PoolCreated(tokenX, tokenY, tickSpacing, pool);
    }
}