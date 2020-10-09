module.exports = {
  accounts: {
    amount: 100, // Number of unlocked accounts
    ether: 1000000, // Initial balance of unlocked accounts (in ether)
  },
  contracts: {
    type: 'truffle', // Contract abstraction to use: 'truffle' for @truffle/contract or 'web3' for web3-eth-contract
    artifactsDir: 'build/contracts', // Directory where contract artifacts are stored
  },
  node: {
    gasLimit: 10e6, // Maximum gas per block
    // When the vmErrorsOnRPCResponse setting value is:
    //    FALSE: thrown errors contain tx hash, blockHash, gasUsed but have a generic error message
    //    TRUE:  thrown errors contain the exact error (out of gas, or revert) but no transaction details
    // The default is TRUE
    // If you need to debug the tx in tenderly, change this to FALSE, otherwise leave set to TRUE.
    vmErrorsOnRPCResponse: true,
  },
};
