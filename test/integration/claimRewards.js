const { balance, expectRevert, ether, send, time } = require('@openzeppelin/test-helpers');
const getQuoteValues = require('../../nexusmutual/test/utils/getQuote.js').getQuoteValues;
const {increaseTimeTo, duration, latestTime} = require('../../nexusmutual/test/utils/increaseTime');
const { toWei, toHex} = require('../../nexusmutual/test/utils/ethTools');
const { assert } = require('chai');
require('chai').should();

const { getValue } = require('./external');
const { hex } = require('../utils');
const setup = require('./setup');

const BN = web3.utils.BN;
const fee = ether('0.002');
const LOCK_REASON_CLAIM = hex('CLA');
const CLA = '0x434c41';
const rewardRateScale = new BN('10').pow(new BN('18'));
const smartConAdd = '0xd0a6e6c54dbc68db5db3a091b171a77407ff7ccf';
const coverPeriod = 61;
const coverDetails = [1, '3362445813369838', '744892736679184', '7972408607'];
const Ownable = artifacts.require('OwnableMock');

contract.only('arInsure', function (accounts) {
//  this.timeout(10000000);
  const [
    owner,
    member1,
    member2,
    member3,
    member4,
    member5,
    staker1,
    staker2,
    sponsor1,
    coverHolder,
  ] = accounts;

  const tokensLockedForVoting = ether('200');
  const validity = 360 * 24 * 60 * 60; // 360 days
  const UNLIMITED_ALLOWANCE = new BN('2')
    .pow(new BN('256'))
    .sub(new BN('1'));

  const initialMemberFunds = ether('2500');

  async function initMembers () {
    const { mr, mcr, pd, tk, tc, cd } = this;

    await mr.addMembersBeforeLaunch([], []);
    (await mr.launched()).should.be.equal(true);

    const minimumCapitalRequirementPercentage = await getValue(ether('2'), pd, mcr);
    await mcr.addMCRData(
      minimumCapitalRequirementPercentage,
      ether('100'),
      ether('2'),
      ['0x455448', '0x444149'],
      [100, 65407],
      20181011, {
        from: owner,
      },
    );
    (await pd.capReached()).toString().should.be.equal('1');

    this.allStakers = [staker1, staker2];
    const members = [member1, member2, member3, member4, member5];
    members.push(...this.allStakers);
    members.push(coverHolder);

    for (const member of members) {
      await mr.payJoiningFee(member, { from: member, value: fee });
      await mr.kycVerdict(member, true);
      await tk.approve(tc.address, UNLIMITED_ALLOWANCE, { from: member });
      await tk.transfer(member, initialMemberFunds);
    }
    await this.tc.lock(CLA, ether('400'), duration.days(300), {
      from: member4
    });

  }
  
  before(setup);
  before(initMembers);

  describe('integration test', function () {
    before( async function (){
      await this.arInsure.addCurrency('0x444149',this.dai.address, {from:owner});
      await this.tk.approve(this.mr.address, UNLIMITED_ALLOWANCE, {from: member5});
      await this.mr.switchMembership(this.arInsure.address,{from:member5});
      await this.mr.payJoiningFee(member5, { from: member5, value: fee });
      await this.mr.kycVerdict(member5, true);
      await this.tk.approve(this.tc.address, UNLIMITED_ALLOWANCE, { from: member5 });
      await this.tk.transfer(member5, initialMemberFunds);
      await this.mr.switchMembership(this.yInsure.address,{from:member5});
      await this.arInsure.nxmTokenApprove(this.tc.address, UNLIMITED_ALLOWANCE, {from:owner});
      await this.yInsure.nxmTokenApprove(this.tc.address, UNLIMITED_ALLOWANCE, {from:owner});
    });

    const currency = hex('ETH');
    describe.skip('#switchMembership()', async function(){
      it('should fail if msg.sender is not owner', async function(){
        await expectRevert.unspecified(this.arInsure.switchMembership(member4,{from:member4}));
      });
      describe('when switched', async function(){
        beforeEach(async function(){
          await this.arInsure.switchMembership(accounts[12]);
        });
        it('should change membership', async function(){
          (await this.mr.checkRole(accounts[12], 2)).should.be.equal(true);
        });
      });
    });

    describe('#buyCover()', async function () {
      let initialCurrencyAssetVarMin;
      let coverID;
      let coverCurr;

      
      it('should be able to buy cover with eth', async function() {
        coverDetails[4] = new BN(coverDetails[4]).addn(1);
        var vrsdata = await getQuoteValues(
          coverDetails,
          toHex('ETH'),
          coverPeriod,
          smartConAdd,
          this.qt.address
        );
        await this.p1.makeCoverBegin(
          smartConAdd,
          toHex('ETH'),
          coverDetails,
          coverPeriod,
          vrsdata[0],
          vrsdata[1],
          vrsdata[2],
          {from: coverHolder, value: coverDetails[1]}
        );
        coverDetails[4] = new BN(coverDetails[4]).addn(1);
        var vrsdata = await getQuoteValues(
          coverDetails,
          toHex(currency),
          coverPeriod,
          smartConAdd,
          this.qt.address
        );
        await this.p1.makeCoverBegin(
          smartConAdd,
          toHex(currency),
          coverDetails,
          coverPeriod,
          vrsdata[0],
          vrsdata[1],
          vrsdata[2],
          {from: coverHolder, value: coverDetails[1]}
        );
        coverDetails[4] = new BN(coverDetails[4]).addn(1);
        vrsdata = await getQuoteValues(
          coverDetails,
          toHex('ETH'),
          coverPeriod,
          smartConAdd,
          this.qt.address
        );
        await this.arInsure.buyCoverWnxmSpot(
          smartConAdd,
          toHex('ETH'),
          coverDetails,
          coverPeriod,
          0,
          vrsdata[0],
          vrsdata[1],
          vrsdata[2],
          {from: coverHolder, value: coverDetails[1]}
        );
      });

      it('should be able to buy cover with dai', async function(){
        coverDetails[4] = new BN(coverDetails[4]).addn(1);
        var vrsdata = await getQuoteValues(
          coverDetails,
          toHex('DAI'),
          coverPeriod,
          smartConAdd,
          this.qt.address
        );
        await this.dai.mint(coverHolder, ether('400'));
        await this.dai.approve(this.p1.address, ether('400'),{from:coverHolder});
        await this.p1.makeCoverUsingCA(
          smartConAdd,
          toHex('DAI'),
          coverDetails,
          coverPeriod,
          vrsdata[0],
          vrsdata[1],
          vrsdata[2],
          {from: coverHolder}
        );
        coverDetails[4] = new BN(coverDetails[4]).addn(1);
        vrsdata = await getQuoteValues(
          coverDetails,
          toHex('DAI'),
          coverPeriod,
          smartConAdd,
          this.qt.address
        );
        await this.dai.approve(this.arInsure.address, ether('400'),{from:coverHolder});
        await this.arInsure.approveToken(this.dai.address);
        const receipt = await this.arInsure.buyCover(
          smartConAdd,
          toHex('DAI'),
          coverDetails,
          coverPeriod,
          vrsdata[0],
          vrsdata[1],
          vrsdata[2],
          {from: coverHolder}
        );
      });

      it('should be able to buy cover with wNXM', async function(){
        coverDetails[4] = new BN(coverDetails[4]).addn(1);
        var vrsdata = await getQuoteValues(
          coverDetails,
          toHex('wNXM'),
          coverPeriod,
          smartConAdd,
          this.qt.address
        );
        await this.dai.mint(coverHolder, ether('400'));
        await this.dai.approve(this.p1.address, ether('400'),{from:coverHolder});
        await this.p1.makeCoverUsingCA(
          smartConAdd,
          toHex('DAI'),
          coverDetails,
          coverPeriod,
          vrsdata[0],
          vrsdata[1],
          vrsdata[2],
          {from: coverHolder}
        );
        coverDetails[4] = new BN(coverDetails[4]).addn(1);
        vrsdata = await getQuoteValues(
          coverDetails,
          toHex('DAI'),
          coverPeriod,
          smartConAdd,
          this.qt.address
        );
        await this.dai.approve(this.arInsure.address, ether('400'),{from:coverHolder});
        await this.arInsure.approveToken(this.dai.address);
        const receipt = await this.arInsure.buyCover(
          smartConAdd,
          toHex('DAI'),
          coverDetails,
          coverPeriod,
          vrsdata[0],
          vrsdata[1],
          vrsdata[2],
          {from: coverHolder}
        );
      });

      it('eth - should fail if msg.value does not match the cover price', async function(){
        coverDetails[4] = new BN(coverDetails[4]).addn(1);
        vrsdata = await getQuoteValues(
          coverDetails,
          toHex('ETH'),
          coverPeriod,
          smartConAdd,
          this.qt.address
        );
        await expectRevert.unspecified(this.arInsure.buyCover(
          smartConAdd,
          toHex('ETH'),
          coverDetails,
          coverPeriod,
          vrsdata[0],
          vrsdata[1],
          vrsdata[2],
          {from: coverHolder, value: new BN(coverDetails[1]).addn(1)}
        ));
      });

      it('dai - should fail if token is not approved', async function(){
        coverDetails[4] = new BN(coverDetails[4]).addn(1);
        vrsdata = await getQuoteValues(
          coverDetails,
          toHex('DAI'),
          coverPeriod,
          smartConAdd,
          this.qt.address
        );
        await this.dai.mint(coverHolder, ether('400'));
        await this.dai.approve(this.arInsure.address, new BN(coverDetails[1]).subn(1),{from:coverHolder});
        await this.arInsure.approveToken(this.dai.address);
        await expectRevert.unspecified(this.arInsure.buyCover(
          smartConAdd,
          toHex('DAI'),
          coverDetails,
          coverPeriod,
          vrsdata[0],
          vrsdata[1],
          vrsdata[2],
          {from: coverHolder}
        ));
      });
    });

    describe('#swapYnft()', async function () {
      let initialCurrencyAssetVarMin;
      let coverID;
      let coverCurr;

      before(async function(){
        coverDetails[4] = new BN(coverDetails[4]).addn(1);
        var vrsdata = await getQuoteValues(
          coverDetails,
          toHex('ETH'),
          coverPeriod,
          smartConAdd,
          this.qt.address
        );
        await this.p1.makeCoverBegin(
          smartConAdd,
          toHex('ETH'),
          coverDetails,
          coverPeriod,
          vrsdata[0],
          vrsdata[1],
          vrsdata[2],
          {from: coverHolder, value: coverDetails[1]}
        );
        coverDetails[4] = new BN(coverDetails[4]).addn(1);
        var vrsdata = await getQuoteValues(
          coverDetails,
          toHex(currency),
          coverPeriod,
          smartConAdd,
          this.qt.address
        );
        await this.p1.makeCoverBegin(
          smartConAdd,
          toHex(currency),
          coverDetails,
          coverPeriod,
          vrsdata[0],
          vrsdata[1],
          vrsdata[2],
          {from: coverHolder, value: coverDetails[1]}
        );
        coverDetails[4] = new BN(coverDetails[4]).addn(1);
        vrsdata = await getQuoteValues(
          coverDetails,
          toHex('ETH'),
          coverPeriod,
          smartConAdd,
          this.qt.address
        );
        await this.yInsure.buyCover(
          smartConAdd,
          toHex('ETH'),
          coverDetails,
          coverPeriod,
          vrsdata[0],
          vrsdata[1],
          vrsdata[2],
          {from: coverHolder, value: coverDetails[1]}
        );
      });

      it('should fail if not activated', async function(){
        const token = await this.yInsure.tokens(0);
        await this.yInsure.approve(this.arInsure.address, 0, {from:coverHolder});
        await expectRevert(this.arInsure.swapYnft(0, {from:coverHolder}),"Swap is not activated yet");
      });

      it('should be able to swap yNFT', async function() {
        await this.arInsure.activateSwap();
        const token = await this.yInsure.tokens(0);
        await this.yInsure.approve(this.arInsure.address, 0, {from:coverHolder});
        await this.arInsure.swapYnft(0, {from:coverHolder});
      });

      it('should fail if msg.sender is not cover holder', async function(){
        coverDetails[4] = new BN(coverDetails[4]).addn(1);
        vrsdata = await getQuoteValues(
          coverDetails,
          toHex('ETH'),
          coverPeriod,
          smartConAdd,
          this.qt.address
        );
        await this.yInsure.buyCover(
          smartConAdd,
          toHex('ETH'),
          coverDetails,
          coverPeriod,
          vrsdata[0],
          vrsdata[1],
          vrsdata[2],
          {from: coverHolder, value: coverDetails[1]}
        );
        const token = await this.yInsure.tokens(1);
        await this.yInsure.approve(this.arInsure.address, 1, {from:coverHolder});
        await expectRevert.unspecified(this.arInsure.swapYnft(1, {from:member4}));
      });

      it("should set coverId as arNFT tokenId", async function(){
        coverDetails[4] = new BN(coverDetails[4]).addn(1);
        vrsdata = await getQuoteValues(
          coverDetails,
          toHex('ETH'),
          coverPeriod,
          smartConAdd,
          this.qt.address
        );
        await this.yInsure.buyCover(
          smartConAdd,
          toHex('ETH'),
          coverDetails,
          coverPeriod,
          vrsdata[0],
          vrsdata[1],
          vrsdata[2],
          {from: coverHolder, value: coverDetails[1]}
        );
        const length = await this.yInsure.balanceOf(coverHolder);
        let tokens = [];
        for(let i =0; i<length; i++){
          tokens.push(await this.yInsure.tokenOfOwnerByIndex(coverHolder, i));
        }
        const tokenId = tokens[length.subn(1)];
        const token = await this.yInsure.tokens(tokenId);
        await this.yInsure.approve(this.arInsure.address, tokenId, {from:coverHolder});
        await this.arInsure.swapYnft(tokenId, {from:coverHolder});
        (await this.arInsure.ownerOf(token.coverId)).should.be.equal(coverHolder);
      });

      it("should be able to batch swap yNFT", async function(){
        coverDetails[4] = new BN(coverDetails[4]).addn(1);
        vrsdata = await getQuoteValues(
          coverDetails,
          toHex('ETH'),
          coverPeriod,
          smartConAdd,
          this.qt.address
        );
        await this.yInsure.buyCover(
          smartConAdd,
          toHex('ETH'),
          coverDetails,
          coverPeriod,
          vrsdata[0],
          vrsdata[1],
          vrsdata[2],
          {from: coverHolder, value: coverDetails[1]}
        );
        coverDetails[4] = new BN(coverDetails[4]).addn(1);
        vrsdata = await getQuoteValues(
          coverDetails,
          toHex('ETH'),
          coverPeriod,
          smartConAdd,
          this.qt.address
        );
        await this.yInsure.buyCover(
          smartConAdd,
          toHex('ETH'),
          coverDetails,
          coverPeriod,
          vrsdata[0],
          vrsdata[1],
          vrsdata[2],
          {from: coverHolder, value: coverDetails[1]}
        );
        coverDetails[4] = new BN(coverDetails[4]).addn(1);
        vrsdata = await getQuoteValues(
          coverDetails,
          toHex('ETH'),
          coverPeriod,
          smartConAdd,
          this.qt.address
        );
        await this.yInsure.buyCover(
          smartConAdd,
          toHex('ETH'),
          coverDetails,
          coverPeriod,
          vrsdata[0],
          vrsdata[1],
          vrsdata[2],
          {from: coverHolder, value: coverDetails[1]}
        );
        const length = await this.yInsure.balanceOf(coverHolder);
        let tokens = [];
        for(let i =0; i<length; i++){
          tokens.push(await this.yInsure.tokenOfOwnerByIndex(coverHolder, i));
        }
        await this.yInsure.setApprovalForAll(this.arInsure.address, true, {from:coverHolder});
        await this.arInsure.batchSwapYnft(tokens, {from:coverHolder});
      });
    });
    describe('#submitClaim()', async function () {
      beforeEach(async function(){
        coverDetails[4] = new BN(coverDetails[4]).addn(1);
        var vrsdata = await getQuoteValues(
          coverDetails,
          toHex('ETH'),
          coverPeriod,
          smartConAdd,
          this.qt.address
        );
        await this.p1.makeCoverBegin(
          smartConAdd,
          toHex('ETH'),
          coverDetails,
          coverPeriod,
          vrsdata[0],
          vrsdata[1],
          vrsdata[2],
          {from: coverHolder, value: coverDetails[1]}
        );
        coverDetails[4] = new BN(coverDetails[4]).addn(1);
        vrsdata = await getQuoteValues(
          coverDetails,
          toHex('ETH'),
          coverPeriod,
          smartConAdd,
          this.qt.address
        );
        await this.arInsure.buyCover(
          smartConAdd,
          toHex('ETH'),
          coverDetails,
          coverPeriod,
          vrsdata[0],
          vrsdata[1],
          vrsdata[2],
          {from: coverHolder, value: coverDetails[1]}
        );
        coverDetails[4] = new BN(coverDetails[4]).addn(1);
        var vrsdata = await getQuoteValues(
          coverDetails,
          toHex('DAI'),
          coverPeriod,
          smartConAdd,
          this.qt.address
        );
        await this.dai.mint(coverHolder, ether('400'));
        await this.dai.approve(this.p1.address, ether('400'),{from:coverHolder});
        await this.p1.makeCoverUsingCA(
          smartConAdd,
          toHex('DAI'),
          coverDetails,
          coverPeriod,
          vrsdata[0],
          vrsdata[1],
          vrsdata[2],
          {from: coverHolder}
        );
        coverDetails[4] = new BN(coverDetails[4]).addn(1);
        vrsdata = await getQuoteValues(
          coverDetails,
          toHex('DAI'),
          coverPeriod,
          smartConAdd,
          this.qt.address
        );
        await this.dai.mint(coverHolder, ether('1000000'));
        await this.dai.approve(this.arInsure.address, ether('400'),{from:coverHolder});
        await this.arInsure.approveToken(this.dai.address);
        await this.arInsure.buyCover(
          smartConAdd,
          toHex('DAI'),
          coverDetails,
          coverPeriod,
          vrsdata[0],
          vrsdata[1],
          vrsdata[2],
          {from: coverHolder}
        );
      });

      it('should fail if msg.sender is not token owner', async function(){
        coverDetails[4] = new BN(coverDetails[4]).addn(1);
        vrsdata = await getQuoteValues(
          coverDetails,
          toHex('ETH'),
          coverPeriod,
          smartConAdd,
          this.qt.address
        );
        await this.arInsure.buyCover(
          smartConAdd,
          toHex('ETH'),
          coverDetails,
          coverPeriod,
          vrsdata[0],
          vrsdata[1],
          vrsdata[2],
          {from: coverHolder, value: coverDetails[1]}
        );
        let length = await this.arInsure.balanceOf(coverHolder);
        let tokenId = await this.arInsure.tokenOfOwnerByIndex(coverHolder, length - 1);
        await expectRevert.unspecified(this.arInsure.submitClaim(tokenId, {from:member4}));
      });
      it('should fail if already submitted and not denied', async function(){
        coverDetails[4] = new BN(coverDetails[4]).addn(1);
        vrsdata = await getQuoteValues(
          coverDetails,
          toHex('ETH'),
          coverPeriod,
          smartConAdd,
          this.qt.address
        );
        await this.arInsure.buyCover(
          smartConAdd,
          toHex('ETH'),
          coverDetails,
          coverPeriod,
          vrsdata[0],
          vrsdata[1],
          vrsdata[2],
          {from: coverHolder, value: coverDetails[1]}
        );
        let length = await this.arInsure.balanceOf(coverHolder);
        let tokenId = await this.arInsure.tokenOfOwnerByIndex(coverHolder, length - 1);
        await this.arInsure.submitClaim(tokenId, {from:coverHolder});
        await expectRevert.unspecified(this.arInsure.submitClaim(tokenId, {from:coverHolder}));
      });
      it('should fail if already redeemed', async function(){
        let length = await this.arInsure.balanceOf(coverHolder);
        let tokenId = await this.arInsure.tokenOfOwnerByIndex(coverHolder, length - 2);
        await this.arInsure.submitClaim(tokenId, {from: coverHolder});
        let clid = (await this.cd.actualClaimLength()) - 1;
        await this.cl.submitCAVote(clid, 1, {from: member4});
        let now = await time.latest();
        let maxVoteTime = await this.cd.maxVotingTime();
        await time.increaseTo(now / 1 + maxVoteTime / 1 + 100);
        let cStatus = await this.cd.getClaimStatusNumber(clid);
        let apiid = await this.pd.allAPIcall((await this.pd.getApilCallLength()) - 1);
        await this.p1.__callback(apiid, '');
        cstatus = await this.cd.getClaimStatusNumber(clid);
        const before = await balance.current(coverHolder);
        await this.arInsure.redeemClaim(tokenId, {from:coverHolder});
        await expectRevert.unspecified(this.arInsure.submitClaim(tokenId, {from:coverHolder}));
      });

      it('should route to ynft if token is swapped from ynft', async function(){
        coverDetails[4] = new BN(coverDetails[4]).addn(100);
        vrsdata = await getQuoteValues(
          coverDetails,
          toHex('ETH'),
          coverPeriod,
          smartConAdd,
          this.qt.address
        );
        await this.yInsure.buyCover(
          smartConAdd,
          toHex('ETH'),
          coverDetails,
          coverPeriod,
          vrsdata[0],
          vrsdata[1],
          vrsdata[2],
          {from: coverHolder, value: coverDetails[1]}
        );
        coverDetails[4] = new BN(coverDetails[4]).addn(1);
        vrsdata = await getQuoteValues(
          coverDetails,
          toHex('ETH'),
          coverPeriod,
          smartConAdd,
          this.qt.address
        );
        await this.yInsure.buyCover(
          smartConAdd,
          toHex('ETH'),
          coverDetails,
          coverPeriod,
          vrsdata[0],
          vrsdata[1],
          vrsdata[2],
          {from: coverHolder, value: coverDetails[1]}
        );
        let length = await this.yInsure.balanceOf(coverHolder);
        let tokenId = await this.yInsure.tokenOfOwnerByIndex(coverHolder, length - 1);
        await this.yInsure.approve(this.arInsure.address,tokenId, {from:coverHolder});
        await this.arInsure.swapYnft(tokenId,{from:coverHolder});
        const token = await this.yInsure.tokens(tokenId);
        await this.arInsure.submitClaim(token.coverId, {from: coverHolder});
      });
      it('should update claimId when submitting denied claim', async function(){
        coverDetails[4] = new BN(coverDetails[4]).addn(1);
        vrsdata = await getQuoteValues(
          coverDetails,
          toHex('ETH'),
          coverPeriod,
          smartConAdd,
          this.qt.address
        );
        await this.yInsure.buyCover(
          smartConAdd,
          toHex('ETH'),
          coverDetails,
          coverPeriod,
          vrsdata[0],
          vrsdata[1],
          vrsdata[2],
          {from: coverHolder, value: coverDetails[1]}
        );
        coverDetails[4] = new BN(coverDetails[4]).addn(1);
        vrsdata = await getQuoteValues(
          coverDetails,
          toHex('ETH'),
          coverPeriod,
          smartConAdd,
          this.qt.address
        );
        await this.yInsure.buyCover(
          smartConAdd,
          toHex('ETH'),
          coverDetails,
          coverPeriod,
          vrsdata[0],
          vrsdata[1],
          vrsdata[2],
          {from: coverHolder, value: coverDetails[1]}
        );
        let length = await this.arInsure.balanceOf(coverHolder);
        let tokenId = await this.arInsure.tokenOfOwnerByIndex(coverHolder, length - 2);
        await this.arInsure.submitClaim(tokenId, {from: coverHolder});
        let clid = (await this.cd.actualClaimLength()) - 1;
        await this.cl.submitCAVote(clid, -1, {from: member4});
        let now = await time.latest();
        let maxVoteTime = await this.cd.maxVotingTime();
        await time.increaseTo(now / 1 + maxVoteTime / 1 + 100);
        let cStatus = await this.cd.getClaimStatusNumber(clid);
        let apiid = await this.pd.allAPIcall((await this.pd.getApilCallLength()) - 1);
        await this.p1.__callback(apiid, '');
        cstatus = await this.cd.getClaimStatusNumber(clid);
        const before = await balance.current(coverHolder);
        const tokenStatus = await this.arInsure.getToken(tokenId);
        (tokenStatus.status).should.be.bignumber.equal(new BN(2));
        await this.arInsure.submitClaim(tokenId, {from:coverHolder});
        (await this.arInsure.claimIds(tokenId)).should.be.bignumber.not.equal(new BN(clid));
      });
    });

    describe('#redeemClaim()', function (){
      beforeEach(async function(){
        coverDetails[4] = new BN(coverDetails[4]).addn(1);
        var vrsdata = await getQuoteValues(
          coverDetails,
          toHex('ETH'),
          coverPeriod,
          smartConAdd,
          this.qt.address
        );
        await this.p1.makeCoverBegin(
          smartConAdd,
          toHex('ETH'),
          coverDetails,
          coverPeriod,
          vrsdata[0],
          vrsdata[1],
          vrsdata[2],
          {from: coverHolder, value: coverDetails[1]}
        );
        coverDetails[4] = new BN(coverDetails[4]).addn(1);
        var vrsdata = await getQuoteValues(
          coverDetails,
          toHex('DAI'),
          coverPeriod,
          smartConAdd,
          this.qt.address
        );
        await this.p1.makeCoverUsingCA(
          smartConAdd,
          toHex('DAI'),
          coverDetails,
          coverPeriod,
          vrsdata[0],
          vrsdata[1],
          vrsdata[2],
          {from: coverHolder}
        );
        await this.dai.mint(coverHolder, ether('400'));
        await this.dai.approve(this.arInsure.address, ether('400'),{from:coverHolder});
      });

      it('should be able to redeem eth - fails because of gasFee', async function(){
        coverDetails[4] = new BN(coverDetails[4]).addn(1);
        vrsdata = await getQuoteValues(
          coverDetails,
          toHex('ETH'),
          coverPeriod,
          smartConAdd,
          this.qt.address
        );
        await this.arInsure.buyCover(
          smartConAdd,
          toHex('ETH'),
          coverDetails,
          coverPeriod,
          vrsdata[0],
          vrsdata[1],
          vrsdata[2],
          {from: coverHolder, value: coverDetails[1]}
        );
        let length = await this.arInsure.balanceOf(coverHolder);
        let tokenId = await this.arInsure.tokenOfOwnerByIndex(coverHolder, length - 1);
        await this.arInsure.submitClaim(tokenId, {from: coverHolder});
        let clid = (await this.cd.actualClaimLength()) - 1;
        await this.cl.submitCAVote(clid, 1, {from: member4});
        let now = await time.latest();
        let maxVoteTime = await this.cd.maxVotingTime();
        await time.increaseTo(now / 1 + maxVoteTime / 1 + 100);
        let cStatus = await this.cd.getClaimStatusNumber(clid);
        let apiid = await this.pd.allAPIcall((await this.pd.getApilCallLength()) - 1);
        await this.ps.processPendingActions(100);
        await this.p1.__callback(apiid, '');
        cstatus = await this.cd.getClaimStatusNumber(clid);
        const before = await balance.current(coverHolder);
        await this.arInsure.redeemClaim(tokenId, {from:coverHolder});
        ((await balance.current(coverHolder)).sub(before)).should.be.bignumber.equal(new BN(ether('1')));
      });

      it('should be able to redeem dai', async function(){
        coverDetails[4] = new BN(coverDetails[4]).addn(1);
        vrsdata = await getQuoteValues(
          coverDetails,
          toHex('DAI'),
          coverPeriod,
          smartConAdd,
          this.qt.address
        );
        await this.arInsure.buyCover(
          smartConAdd,
          toHex('DAI'),
          coverDetails,
          coverPeriod,
          vrsdata[0],
          vrsdata[1],
          vrsdata[2],
          {from: coverHolder}
        );
        let length = await this.arInsure.balanceOf(coverHolder);
        let tokenId = await this.arInsure.tokenOfOwnerByIndex(coverHolder, length - 1);
        await this.arInsure.submitClaim(tokenId, {from: coverHolder});
        let clid = (await this.cd.actualClaimLength()) - 1;
        await this.cl.submitCAVote(clid, 1, {from: member4});
        let now = await time.latest();
        let maxVoteTime = await this.cd.maxVotingTime();
        await time.increaseTo(now / 1 + maxVoteTime / 1 + 100);
        let cStatus = await this.cd.getClaimStatusNumber(clid);
        let apiid = await this.pd.allAPIcall((await this.pd.getApilCallLength()) - 1);
        await this.ps.processPendingActions(100);
        await this.p1.__callback(apiid, '');
        cStatus = await this.cd.getClaimStatusNumber(clid);
        const before = await this.dai.balanceOf(coverHolder);
        await this.arInsure.redeemClaim(tokenId, {from:coverHolder});
        ((await this.dai.balanceOf(coverHolder)).sub(before)).should.be.bignumber.equal(new BN(ether('1')));
      });

      it('should fail if not submitted', async function(){
        coverDetails[4] = new BN(coverDetails[4]).addn(1);
        vrsdata = await getQuoteValues(
          coverDetails,
          toHex('ETH'),
          coverPeriod,
          smartConAdd,
          this.qt.address
        );
        await this.arInsure.buyCover(
          smartConAdd,
          toHex('ETH'),
          coverDetails,
          coverPeriod,
          vrsdata[0],
          vrsdata[1],
          vrsdata[2],
          {from: coverHolder, value: coverDetails[1]}
        );
        let length = await this.arInsure.balanceOf(coverHolder);
        let tokenId = await this.arInsure.tokenOfOwnerByIndex(coverHolder, length - 1);
        await expectRevert.unspecified(this.arInsure.redeemClaim(tokenId, {from:coverHolder}));
      });

      it('should fail if denied', async function(){
        coverDetails[4] = new BN(coverDetails[4]).addn(1);
        vrsdata = await getQuoteValues(
          coverDetails,
          toHex('ETH'),
          coverPeriod,
          smartConAdd,
          this.qt.address
        );
        await this.arInsure.buyCover(
          smartConAdd,
          toHex('ETH'),
          coverDetails,
          coverPeriod,
          vrsdata[0],
          vrsdata[1],
          vrsdata[2],
          {from: coverHolder, value: coverDetails[1]}
        );
        let length = await this.arInsure.balanceOf(coverHolder);
        let tokenId = await this.arInsure.tokenOfOwnerByIndex(coverHolder, length - 1);
        await this.arInsure.submitClaim(tokenId, {from:coverHolder});
        let clid = (await this.cd.actualClaimLength()) - 1;
        await this.cl.submitCAVote(clid, -1, {from: member4});
        let now = await time.latest();
        let maxVoteTime = await this.cd.maxVotingTime();
        await time.increaseTo(now / 1 + maxVoteTime / 1 + 100);
        let cStatus = await this.cd.getClaimStatusNumber(clid);
        let apiid = await this.pd.allAPIcall((await this.pd.getApilCallLength()) - 1);
        await this.ps.processPendingActions(100);
        await this.p1.__callback(apiid, '');
        cStatus = await this.cd.getClaimStatusNumber(clid);
        const tokenStatus = await this.arInsure.getToken(tokenId);
        (tokenStatus.status).should.be.bignumber.equal(new BN(2));
        const before = await this.dai.balanceOf(coverHolder);
        await expectRevert.unspecified(this.arInsure.redeemClaim(tokenId, {from:coverHolder}));
      });

      it('should fail to redeem twice', async function(){
        coverDetails[4] = new BN(coverDetails[4]).addn(1);
        vrsdata = await getQuoteValues(
          coverDetails,
          toHex('ETH'),
          coverPeriod,
          smartConAdd,
          this.qt.address
        );
        await this.arInsure.buyCover(
          smartConAdd,
          toHex('ETH'),
          coverDetails,
          coverPeriod,
          vrsdata[0],
          vrsdata[1],
          vrsdata[2],
          {from: coverHolder, value: coverDetails[1]}
        );
        await send.ether(coverHolder, this.arInsure.address, ether('3'));
        let length = await this.arInsure.balanceOf(coverHolder);
        let tokenId = await this.arInsure.tokenOfOwnerByIndex(coverHolder, length - 2);
        await this.arInsure.submitClaim(tokenId, {from: coverHolder});
        let clid = (await this.cd.actualClaimLength()) - 1;
        await this.cl.submitCAVote(clid, 1, {from: member4});
        let now = await time.latest();
        let maxVoteTime = await this.cd.maxVotingTime();
        await time.increaseTo(now / 1 + maxVoteTime / 1 + 100);
        let cStatus = await this.cd.getClaimStatusNumber(clid);
        let apiid = await this.pd.allAPIcall((await this.pd.getApilCallLength()) - 1);
        await this.p1.__callback(apiid, '');
        cStatus = await this.cd.getClaimStatusNumber(clid);
        const before = await balance.current(coverHolder);
        await this.arInsure.redeemClaim(tokenId, {from:coverHolder});
        await expectRevert.unspecified(this.arInsure.redeemClaim(tokenId, {from:coverHolder}));
      });
    });
  });
});
