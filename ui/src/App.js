import './App.css';
import SwapForm from './components/SwapForm.js';
import MetaMask from './components/MetaMask.js';
import EventsFeed from './components/EventsFeed.js';
import { MetaMaskProvider } from './contexts/MetaMask';

const config = {
  token0Address: '0x5FbDB2315678afecb367f032d93F642f64180aa3',
  token1Address: '0x9fe46736679d2d9a65f0992f2272de9f3c7fa6e0',
  poolAddress: '0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9',
  managerAddress: '0x5FC8d32690cc91D4c39d9d3abcBD16989F875707',
  ABIs: {
    'ERC20': require('./abi/ERC20.json'),
    'Pool': require('./abi/Pool.json'),
    'Manager': require('./abi/Manager.json')
  }
};

const App = () => {
  return (
    <MetaMaskProvider>
      <div className="App flex flex-col justify-between items-center w-full h-full">
        <MetaMask />
        <SwapForm config={config} />
        <footer>
          <EventsFeed config={config} />
        </footer>
      </div>
    </MetaMaskProvider>
  );
}

export default App;
