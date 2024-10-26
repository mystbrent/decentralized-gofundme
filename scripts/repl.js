// scripts/repl.js
const hre = require("hardhat");
const { ethers } = require("hardhat");
const { Wallet } = require("ethers");

// Mainnet contract addresses we'll use on the fork
const SABLIER_V2_LOCKUP_LINEAR = "0xAFb979d9afAd1aD27C5eFf4E27226E3AB9e5dCC9";
const USDC = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
const WHALE_ADDRESS = "0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503"; // Rich USDC account on fork

class GoFundMeREPL {
  constructor() {
    this.contract = null;
    this.stablecoin = null;
    this.sablier = null;
    this.testAccounts = [
      new ethers.Wallet(
        "0xa89228f6057e41b9b7ba5ccd8209083893562043d0c889cde50a48912af8f416",
        hre.ethers.provider
      ),
    ];
    this.owner = null;
  }

  async initialize() {
    console.log("Initializing REPL on forked network...");

    // Get the owner signer
    const [owner] = await ethers.getSigners();
    this.owner = owner;
    console.log('owner:', owner.address)

    // Create 20 test accounts
    this.testAccounts = Array(20).fill().map(() => Wallet.createRandom().connect(ethers.provider));

    console.log("Created test accounts:");
    this.testAccounts.forEach((account, index) => {
      console.log(`account ${index}:`, account.address);
    });

    // Connect to existing contracts on fork
    this.stablecoin = await ethers.getContractAt("IERC20", USDC);
    this.sablier = await ethers.getContractAt("ISablierV2LockupLinear", SABLIER_V2_LOCKUP_LINEAR);
    
    // Fund test accounts with ETH and USDC
    const TEST_AMOUNT = ethers.utils.parseUnits("10000", 6); // 10k USDC

    for (let i = 0; i < this.testAccounts.length; i++) {
      // Fund with ETH
      await owner.sendTransaction({
        to: this.testAccounts[i].address,
        value: ethers.utils.parseEther("1.0")
      });

      // Fund with USDC using a custom function
      await this.fundAccountWithUSDC(this.testAccounts[i].address, TEST_AMOUNT);
      console.log(`🪙 Test account ${i} funded with 1 ETH and 10k USDC`);
    }

    // Deploy our contract
    const GoFundMe = await ethers.getContractFactory("DecentralizedGoFundMe");
    this.contract = await GoFundMe.deploy(
      USDC,
      owner.address,
      SABLIER_V2_LOCKUP_LINEAR,
      [this.testAccounts[0].address, this.testAccounts[1].address], // Two test recipients
      [5000, 5000] // 50-50 split
    );

    await this.contract.deployed();
    console.log(`\n📜 Contracts ready on fork:`);
    console.log(`GoFundMe: ${this.contract.address}`);
    console.log(`Using USDC: ${USDC}`);
    console.log(`Using Sablier: ${SABLIER_V2_LOCKUP_LINEAR}\n`);
    
    return this;
  }

  async fundAccountWithUSDC(address, amount) {
    // This function will manipulate the USDC balance directly
    await hre.network.provider.send("hardhat_setStorageAt", [
      USDC,
      ethers.utils.keccak256(ethers.utils.defaultAbiCoder.encode(["uint256", "uint256"], [address, 9])),
      ethers.utils.defaultAbiCoder.encode(["uint256"], [amount])
    ]);
  }

  // Helper to format USDC amounts
  fmt(amount) {
    return ethers.utils.formatUnits(amount, 6);
  }

  // Helper to parse USDC amounts
  parse(amount) {
    return ethers.utils.parseUnits(amount.toString(), 6);
  }

  async donate(amount, accountIndex = 2) {
    const donor = this.testAccounts[accountIndex];
    const donationAmount = this.parse(amount);

    await this.stablecoin.connect(donor).approve(this.contract.address, donationAmount);
    await this.contract.connect(donor).donate(donationAmount);
    
    console.log(`💸 ${amount} USDC donated from test account ${accountIndex}`);
    return this.getDonorInfo(donor.address);
  }

  async startStreaming() {
    await this.contract.startStreaming();
    console.log(`🌊 Streaming started`);
    return this.getContractState();
  }

  async vote(accountIndex = 2) {
    await this.contract.connect(this.testAccounts[accountIndex]).vote();
    console.log(`🗳️ Vote cast from test account ${accountIndex}`);
    return this.getVotingState();
  }

  async getContractState() {
    const [totalRaised, isStreaming, isCancelled] = await Promise.all([
      this.contract.totalRaised(),
      this.contract.isStreaming(),
      this.contract.isCancelled()
    ]);

    return {
      totalRaised: this.fmt(totalRaised),
      isStreaming,
      isCancelled
    };
  }

  async getBalances(accountIndices = [0, 1, 2, 3]) {
    const balances = {};
    for (const i of accountIndices) {
      const address = this.testAccounts[i].address;
      balances[`Account ${i}`] = this.fmt(await this.stablecoin.balanceOf(address));
    }
    return balances;
  }

  async quickTest() {
    console.log("\n🧪 Running quick test...\n");

    console.log("1️⃣ Initial balances:");
    console.log(await this.getBalances());

    console.log("\n2️⃣ Making donations:");
    await this.donate(1000); // 1k USDC
    await this.donate(2000, 3); // 2k USDC
    console.log(await this.getContractState());

    console.log("\n3️⃣ Starting streams:");
    await this.startStreaming();

    console.log("\n4️⃣ Checking stream details:");
    const recipient = await this.contract.recipients(0);
    if (recipient.streamId.toString() !== "0") {
      const stream = await this.sablier.getStream(recipient.streamId);
      console.log({
        amount: this.fmt(stream.amounts.deposited),
        start: new Date(stream.startTime * 1000).toLocaleString(),
        end: new Date(stream.endTime * 1000).toLocaleString()
      });
    }

    console.log("\n5️⃣ Testing voting:");
    await this.vote(2);
    await this.vote(3);
    
    console.log("\n6️⃣ Final balances:");
    console.log(await this.getBalances());
  }
}

async function main() {
  const repl = await new GoFundMeREPL().initialize();
  
  global.repl = repl;
  global.ethers = ethers;
  
  console.log(`
    🚀 Hackathon GoFundMe REPL Ready 🚀
    
    Quick commands:
    await repl.donate(100, 2)    // Donate 100 USDC from account 2
    await repl.startStreaming()  // Start streams
    await repl.vote(2)          // Vote from account 2
    await repl.getBalances()    // Check USDC balances
    await repl.quickTest()      // Run all basic tests
    
    Test accounts: repl.testAccounts[0-19]
  `);

  process.stdin.resume();
}

if (require.main === module) {
  main().catch(console.error);
}

module.exports = { GoFundMeREPL };
