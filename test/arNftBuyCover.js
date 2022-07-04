const { expect } = require("chai");
const { providers } = require("ethers");
const { ethers } = require("hardhat");

const weth9_address = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
const uniswapV2Router02_address = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";

describe("arNFT contract", function () {
  let owner;
  let addr1;
  let addr2;
  let addrs;

  let YearnZapper;
  let yearnZapper;

  let weth9;
  let dai;
  let yvdai_ERC20;

  before("Deploy YearnZapper contract", async function () {
    [owner, addr1, addr2, ...addrs] = await ethers.getSigners();
    YearnZapper = await ethers.getContractFactory("YearnZapper");
    yearnZapper = await YearnZapper.deploy();
    await yearnZapper.deployed();

    weth9 = await ethers.getContractAt("contracts/interfaces/IWETH9.sol:IWETH9", weth9_address);
    dai = await ethers.getContractAt("contracts/interfaces/IERC20.sol:IERC20", dai_address);
    yvdai_ERC20 = await ethers.getContractAt("contracts/interfaces/IERC20.sol:IERC20", yvDai_address);

    await owner.sendTransaction({
      to: addr1.address,
      value: ethers.utils.parseEther("1.1")});
    let valueTemp = await yvdai_ERC20.balanceOf(addr1.address);
    await yvdai_ERC20.connect(addr1).transfer(ethers.Wallet.createRandom().address, valueTemp);
  });

  it("Should have more yvDAI balance after WETH -> DAI -> yvDAI", async function() {
    console.log("------------------------------");

    let yvdai_before = await checkYvDaiBalance(addr1.address);

    await weth9.connect(addr1).deposit({ value: ethers.utils.parseEther("1") });
    await weth9.connect(addr1).approve(yearnZapper.address, ethers.utils.parseEther("1"));
    const setSwapTx = await yearnZapper.connect(addr1).deposit(weth9_address, yvDai_address, ethers.utils.parseEther("1"), 1);
    await setSwapTx.wait();
    console.log("Tx: WETH -> DAI -> yvDAI")

    let yvdai_after = await checkYvDaiBalance(addr1.address);

    expect(yvdai_after).to.be.above(yvdai_before);
  });

  it("Should have no yvDAI in wallet, but more DAI after the tx", async function() {
    console.log("------------------------------");

    let yvdai_before2 = await checkYvDaiBalance(addr1.address);
    let dai_before2 = await checkDaiBalance(addr1.address);
    
    await yvdai_ERC20.connect(addr1).approve(yearnZapper.address, yvdai_before2);
    const withdrawTx = await yearnZapper.connect(addr1).yvWithdraw(yvDai_address, yvdai_before2);
    withdrawTx.wait();
    console.log("Tx: yvDAI -> DAI")

    let yvdai_after2 = await checkYvDaiBalance(addr1.address);
    let dai_after2 = await checkDaiBalance(addr1.address);

    expect(yvdai_after2).to.be.below(yvdai_before2);
  });

  async function checkYvDaiBalance(address){
    let yvdai_balance = await yvdai_ERC20.balanceOf(address);
    let yvdb2 = await ethers.utils.formatUnits(yvdai_balance, 18);
    console.log("yvDAI balance: " + yvdb2);
    return yvdai_balance;
  };

  async function checkDaiBalance(address) {
    let dai_balance = await dai.balanceOf(address);
    let db2 = ethers.utils.formatUnits(dai_balance, 18);
    console.log("DAI balance : " + db2);
    return dai_balance;
  };

  async function giveBalances(address) {
    console.log("DAI: " + await dai.balanceOf(address));
    console.log("WETH: " + await weth9.balanceOf(address));
    console.log("WyvDAI: " + await yvdai_ERC20.balanceOf(address));
    console.log("ETH: " + ethers.utils.formatEther(await ethers.provider.getBalance(address)));
  }
});



