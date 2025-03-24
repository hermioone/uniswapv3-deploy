const config = {
  wethAddress: '0x5FbDB2315678afecb367f032d93F642f64180aa3',
  factoryAddress: '0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9',
  managerAddress: '0x5FC8d32690cc91D4c39d9d3abcBD16989F875707',
  quoterAddress: '0xa513E6E4b8f2a923D98304ec87F64353C4D5C853',
  ABIs: {
    'ERC20': require('./abi/ERC20.json'),
    'Factory': require('./abi/Factory.json'),
    'Manager': require('./abi/Manager.json'),
    'Pool': require('./abi/Pool.json'),
    'Quoter': require('./abi/Quoter.json')
  }
};

config.tokens = {};
// WETH 是 tokenX，USDC 是 tokenY，WETH 的 address 应该小于 USDC 的 address（如果要保持 price > 1 的话）
config.tokens[config.wethAddress] = { symbol: 'WETH' };
config.tokens['0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0'] = { symbol: 'USDC' };

export default config;