const config = {
  token0Address: '0x5FbDB2315678afecb367f032d93F642f64180aa3',
  token1Address: '0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0',
  poolAddress: '0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9',
  managerAddress: '0x5FC8d32690cc91D4c39d9d3abcBD16989F875707',
  quoterAddress: '0x0165878A594ca255338adfa4d48449f69242Eb8F',
  ABIs: {
    'ERC20': require('./abi/ERC20.json'),
    'Pool': require('./abi/Pool.json'),
    'Manager': require('./abi/Manager.json'),
    'Quoter': require('./abi/Quoter.json')
  }
};

export default config;