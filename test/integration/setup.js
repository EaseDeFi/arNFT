const { BN, ether, time } = require('@openzeppelin/test-helpers');
const { assert } = require('chai');
const { hex, sleep } = require('../utils');

// external
const DAI = artifacts.require('MockDAIMintable');
const MKR = artifacts.require('MockMKR');
const DSValue = artifacts.require('NXMDSValueMock');
const FactoryMock = artifacts.require('FactoryMock');
const ExchangeMock = artifacts.require('ExchangeMock');
const ExchangeMKRMock = artifacts.require('ExchangeMock');
const OwnedUpgradeabilityProxy = artifacts.require('OwnedUpgradeabilityProxy');

// nexusmutual
const NXMToken = artifacts.require('NXMToken');
const NXMaster = artifacts.require('NXMasterMock');
const Claims = artifacts.require('Claims');
const ClaimsData = artifacts.require('ClaimsDataMock');
const ClaimsReward = artifacts.require('ClaimsReward');
const MCR = artifacts.require('MCR');
const TokenData = artifacts.require('TokenDataMock');
const TokenFunctions = artifacts.require('TokenFunctions');
const TokenController = artifacts.require('TokenController');
const Pool1 = artifacts.require('Pool1Mock');
const Pool2 = artifacts.require('Pool2');
const PoolData = artifacts.require('PoolDataMock');
const Quotation = artifacts.require('Quotation');
const QuotationData = artifacts.require('QuotationData');
const Governance = artifacts.require('GovernanceMock');
const ProposalCategory = artifacts.require('ProposalCategoryMock');
const MemberRoles = artifacts.require('MemberRoles');
const PooledStaking = artifacts.require('PooledStaking');
const MintableERC20 = artifacts.require('MintableERC20');
const ARInsure = artifacts.require('arNFT');
const YInsure = artifacts.require('yInsure');
const Ownable = artifacts.require('OwnableMock');

const QE = '0x51042c4d8936a7764d18370a6a0762b860bb8e07';
const INITIAL_SUPPLY = ether('1500000');
const EXCHANGE_TOKEN = ether('10000');
const EXCHANGE_ETHER = ether('10');
const POOL_ETHER = ether('3500');
const POOL_DAI = ether('900000');

const getProxyFromMaster = async (master, contract, code) => {
  const address = await master.getLatestAddress(hex(code));
  return contract.at(address);
};

async function setup () {

  const ownable = await Ownable.new();
  const owner = await ownable.owner();

  // deploy external contracts
  const dai = await DAI.new();
  const mkr = await MKR.new();
  const dsv = await DSValue.new(owner);
  const factory = await FactoryMock.new();
  const exchange = await ExchangeMock.new(dai.address, factory.address);
  const exchangeMKR = await ExchangeMKRMock.new(mkr.address, factory.address);

  // initialize external contracts
  await factory.setFactory(dai.address, exchange.address);
  await factory.setFactory(mkr.address, exchangeMKR.address);
  await dai.transfer(exchange.address, EXCHANGE_TOKEN);
  await mkr.transfer(exchangeMKR.address, EXCHANGE_TOKEN);
  await exchange.recieveEther({ value: EXCHANGE_ETHER });
  await exchangeMKR.recieveEther({ value: EXCHANGE_ETHER });

  // nexusmutual contracts
  const cl = await Claims.new();
  const cd = await ClaimsData.new();
  const cr = await ClaimsReward.new();

  const p1 = await Pool1.new();
  const p2 = await Pool2.new(factory.address);
  const pd = await PoolData.new(owner, dsv.address, dai.address);

  const mcr = await MCR.new();

  const tk = await NXMToken.new(owner, INITIAL_SUPPLY);
  const tc = await TokenController.new();
  const td = await TokenData.new(owner);
  const tf = await TokenFunctions.new();

  const qt = await Quotation.new();
  const qd = await QuotationData.new(QE, owner);

  const gvImpl = await Governance.new();
  const pcImpl = await ProposalCategory.new();
  const mrImpl = await MemberRoles.new();
  const psImpl = await PooledStaking.new();

  const addresses = [
    qd.address,
    td.address,
    cd.address,
    pd.address,
    qt.address,
    tf.address,
    tc.address,
    cl.address,
    cr.address,
    p1.address,
    p2.address,
    mcr.address,
    gvImpl.address,
    pcImpl.address,
    mrImpl.address,
    psImpl.address,
  ];

  const masterImpl = await NXMaster.new();
  const masterProxy = await OwnedUpgradeabilityProxy.new(masterImpl.address);
  const master = await NXMaster.at(masterProxy.address);

  await master.initiateMaster(tk.address);
  await master.addPooledStaking();
  await master.addNewVersion(addresses);

  const ps = await getProxyFromMaster(master, PooledStaking, 'PS');
  await ps.migrateStakers('1');
  assert(await ps.initialized(), 'Pooled staking contract should have been initialized');

  // fetch proxy contract addresses
  const gvProxyAddress = await master.getLatestAddress(hex('GV'));
  const pcProxyAddress = await master.getLatestAddress(hex('PC'));

  // transfer master ownership and init governance
  await masterProxy.transferProxyOwnership(gvProxyAddress);

  // init governance
  const gv = await Governance.at(gvProxyAddress);
  const pc = await ProposalCategory.at(pcProxyAddress);

  await gv._initiateGovernance();
  await pc.proposalCategoryInitiate();
  await pc.updateCategoryActionHashes();

  // fund pools
  await p1.sendEther({ from: owner, value: POOL_ETHER });
  await p2.sendEther({ from: owner, value: POOL_ETHER });
  await dai.transfer(p2.address, POOL_DAI);

  // add mcr
  await mcr.addMCRData(
    13000,
    ether('1000'),
    ether('70000'),
    [hex('ETH'), hex('DAI')],
    [100, 15517],
    20190103,
  );

  await p2.saveIADetails(
    [hex('ETH'), hex('DAI')],
    [100, 15517],
    20190103,
    true,
  );

  const external = { dai, mkr, dsv, factory, exchange, exchangeMKR };
  const instances = { tk, qd, td, cd, pd, qt, tf, cl, cr, p1, p2, mcr };
  const proxies = {
    tc: await getProxyFromMaster(master, TokenController, 'TC'),
    gv: await getProxyFromMaster(master, Governance, 'GV'),
    pc: await getProxyFromMaster(master, ProposalCategory, 'PC'),
    mr: await getProxyFromMaster(master, MemberRoles, 'MR'),
    ps,
  };

  await proxies.mr.payJoiningFee(owner, { from: owner, value: ether('0.002') });
  await proxies.mr.kycVerdict(owner, true);
  await tk.transfer(owner, new BN(37500));

  await proxies.mr.addInitialABMembers([owner]);

  const roundsStartTimeSecondsUntilStart = 10;
  const latest = (await time.latest()).toNumber();
  const roundsStartTime = latest + roundsStartTimeSecondsUntilStart;
  const roundDuration = 7 * 24 * 60 * 60;

  const mockTokenA = await MintableERC20.new('MockTokenA', 'MTA');

  const yInsure = await YInsure.new(0,master.address);
  const arInsure = await ARInsure.new(master.address, yInsure.address, tk.address);
  await time.increase(roundsStartTimeSecondsUntilStart + 10);

  Object.assign(this, {
    master,
    arInsure,
    yInsure,
    ...external,
    ...instances,
    ...proxies,
    mockTokenA,
  });
}

module.exports = setup;
