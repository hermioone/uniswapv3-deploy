const { network, getNamedAccounts, ethers } = require("hardhat");
const { developmentChains, networkConfig } = require("../helper-hardhat-config");

module.exports = async ({ getNamedAccounts, deployments }) => {
	const { deploy, log } = deployments;
	const { deployer } = await getNamedAccounts();
	log("************ Start to deploy uniswapV3 by ", deployer);

	const ethAddr = (await deployments.get("WETH")).address;
	const usdcAddr = (await deployments.get("USDC")).address;

	const pool = await deploy("UniswapV3Pool", {
		contract: "UniswapV3Pool",
		from: deployer,
		log: true,
		args: [ethAddr, usdcAddr, 1, 0],
	});

    await deploy("UniswapV3Manager", {
        contract: "UniswapV3Manager",
        from: deployer,
        log: true,
    });

};
