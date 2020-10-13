
require('@openzeppelin/test-helpers');
const { shouldBehaveLikeOwnable } = require('./Ownable.behavior');

const Ownable = artifacts.require('OwnableMock');

contract('Ownable', function (accounts) {
  const [ owner, ...otherAccounts ] = accounts;

  beforeEach(async function () {
    this.ownable = await Ownable.new({ from: owner });
  });

  shouldBehaveLikeOwnable(owner, otherAccounts);
});
