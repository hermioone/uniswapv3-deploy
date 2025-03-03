const { network, ethers } = require("hardhat");
const { developmentChains, networkConfig } = require("../helper-hardhat-config");

module.exports = async ({ getNamedAccounts, deployments }) => {
	const { deploy, log } = deployments;
    const { deployer } = await getNamedAccounts();
    const signer = await ethers.getSigner(deployer);
    const tokenOwner = (await ethers.getSigners())[2].address;
    log("********** tokenOwner: ", tokenOwner);

    if (developmentChains.includes(network.name)) {
        log('************ Test network detected! Start to deploy ETH and USDC by ', deployer);
        const eth = await deploy("WETH", {
            contract: "ERC20Mintable",
            from: deployer,
            log: true,
            args: ["Ether", "ETH"],
            waitConfirmations: network.config.blockConfirmations,
        });
        log("('************ WETH deployed successfully...");
        const ethAddr = (await deployments.get('WETH')).address;
        log("********** ethAddr: ", ethAddr)
        const ethContract = await ethers.getContractAt('ERC20Mintable', ethAddr, signer);
        await ethContract.mint(tokenOwner, BigInt(1000 * (10 ** 18)));
        await deploy("USDC", {
            contract: "ERC20Mintable",
            from: deployer,
            log: true,
            args: ["USDC", "USDC"],
            waitConfirmations: network.config.blockConfirmations,
        });
        const usdcAddr = (await deployments.get('USDC')).address;
        const usdcContract = await ethers.getContractAt('ERC20Mintable', usdcAddr, signer);
        await usdcContract.mint(tokenOwner, BigInt(1000000 * (10 ** 18)));
        log("('************ USDC deployed successfully...");
    }
};

module.exports.tags = ["mocks"];

