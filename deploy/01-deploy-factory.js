const { ethers, network, getNamedAccounts, deployments } = require("hardhat");
const { developmentChains, networkConfig } = require("../helper-hardhat-config");

module.exports = async ({getNamedAccounts, deployments}) => {
    const { deploy, log } = deployments;
	const { deployer } = await getNamedAccounts();

    await deploy("UniswapV3Factory", {
		contract: "UniswapV3Factory",
		from: deployer,
		log: true,
	});
}
