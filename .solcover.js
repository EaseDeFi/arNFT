module.exports = {
  norpc: true,
  testCommand: 'npm test',
  providerOptions: {
    default_balance_ether: 1000000,
    gasPrice: "0x00"
  },
  compileCommand: 'npm run compile',
  skipFiles: [
    'Migrations.sol',
    'mocks',
    'nexusmutual'
  ]
}

