module.exports = {
  norpc: true,
  testCommand: 'npm test',
  compileCommand: 'npm run compile-all',
  skipFiles: [
    'Migrations.sol',
    'mocks'
  ]
}

