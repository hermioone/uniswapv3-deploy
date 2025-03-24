const { network, getNamedAccounts, ethers } = require("hardhat");
const { developmentChains, networkConfig } = require("../helper-hardhat-config");
const JSBI = require('jsbi'); // 用于大整数计算

// sqrtP 函数实现
function sqrtP(price) {
    return BigInt(Math.sqrt(price) * (2 ** 96));
}

module.exports = async ({ getNamedAccounts, deployments }) => {
	const { deploy, log } = deployments;
	const { deployer } = await getNamedAccounts();
	const signer = await ethers.getSigner(deployer);
	log("************ Start to deploy uniswapV3 by ", deployer);

	const ethAddr = (await deployments.get("WETH")).address;
	const usdcAddr = (await deployments.get("USDC")).address;
	const factoryAddress = (await deployments.get("UniswapV3Factory")).address;

    await deploy("UniswapV3Manager", {
        contract: "UniswapV3Manager",
        from: deployer,
        log: true,
		args: [factoryAddress]
    });
	const managerAddress = (await deployments.get("UniswapV3Manager")).address;
	const manager = await ethers.getContractAt("UniswapV3Manager", managerAddress, signer);
	const tx = await manager.createAndInitializePoolIfNecessary(ethAddr, usdcAddr, 60, sqrtP(5000));
	const receipt = await tx.wait();

	await deploy("UniswapV3Quoter", {
		contract: "UniswapV3Quoter",
		from: deployer,
		log: true,
		args: [factoryAddress]
	});

};
