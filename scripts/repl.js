// scripts/repl.js
const hre = require("hardhat");
const { ethers } = require("hardhat");
const { Wallet } = require("ethers");

// Mainnet contract addresses we'll use on the fork
const SABLIER_V2_LOCKUP_LINEAR = "0xAFb979d9afAd1aD27C5eFf4E27226E3AB9e5dCC9";
const USDC = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";

class GoFundMeREPL {
  constructor() {
    this.contract = null;
    this.stablecoin = null;
    this.sablier = null;
    this.testAccounts = [];
    this.owner = null;
  }

  async initialize() {
    console.log("\n🚀 Initializing GoFundMe Demo Environment...\n");

    // Get the owner signer
    const [owner] = await ethers.getSigners();
    this.owner = owner;
    console.log('👤 Admin:', owner.address);

    // Create test accounts
    this.testAccounts = Array(5).fill().map(() => Wallet.createRandom().connect(ethers.provider));

    console.log("\n📋 Created test accounts:");
    console.log("Recipients:");
    console.log(`- Charity A: ${this.testAccounts[0].address}`);
    console.log(`- Charity B: ${this.testAccounts[1].address}`);
    console.log("\nDonors:");
    console.log(`- Major Donor: ${this.testAccounts[2].address}`);
    console.log(`- Small Donor 1: ${this.testAccounts[3].address}`);
    console.log(`- Small Donor 2: ${this.testAccounts[4].address}\n`);

    // Connect to existing contracts on fork
    this.stablecoin = await ethers.getContractAt("IERC20", USDC);
    this.sablier = await ethers.getContractAt("ISablierV2LockupLinear", SABLIER_V2_LOCKUP_LINEAR);
    
    // Fund test accounts
    for (let i = 0; i < this.testAccounts.length; i++) {
      // Fund with ETH for gas
      await owner.sendTransaction({
        to: this.testAccounts[i].address,
        value: ethers.utils.parseEther("1.0")
      });

      // Fund with different USDC amounts based on role
      const usdcAmount = i === 2 
        ? ethers.utils.parseUnits("100000", 6)  // Major donor: 100k USDC
        : ethers.utils.parseUnits("10000", 6);  // Others: 10k USDC
        
      await this.fundAccountWithUSDC(this.testAccounts[i].address, usdcAmount);
    }

    console.log("💰 Funded all accounts with ETH and USDC\n");

    // Deploy main contract
    console.log("📜 Deploying GoFundMe contract...");
    const GoFundMe = await ethers.getContractFactory("DecentralizedGoFundMe");
    this.contract = await GoFundMe.deploy(
      USDC,
      owner.address,
      SABLIER_V2_LOCKUP_LINEAR,
      [this.testAccounts[0].address, this.testAccounts[1].address], // Two charities
      [5000, 5000] // 50-50 split
    );

    await this.contract.deployed();
    console.log(`✅ Contract deployed to: ${this.contract.address}\n`);
    
    return this;
  }

  async fundAccountWithUSDC(address, amount) {
    await hre.network.provider.send("hardhat_setStorageAt", [
      USDC,
      ethers.utils.keccak256(ethers.utils.defaultAbiCoder.encode(["uint256", "uint256"], [address, 9])),
      ethers.utils.defaultAbiCoder.encode(["uint256"], [amount])
    ]);
  }

  fmt(amount) {
    return ethers.utils.formatUnits(amount, 6);
  }

  parse(amount) {
    return ethers.utils.parseUnits(amount.toString(), 6);
  }

  async sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  async demonstrateFullFlow() {
    console.log("\n🎬 Starting GoFundMe Demonstration\n");

    // 1. Show initial balances
    console.log("📊 Initial USDC Balances:");
    console.log("Charities:");
    console.log(`Charity A: ${await this.getBalance(this.testAccounts[0].address)} USDC`);
    console.log(`Charity B: ${await this.getBalance(this.testAccounts[1].address)} USDC`);
    console.log("\nDonors:");
    console.log(`Major Donor: ${await this.getBalance(this.testAccounts[2].address)} USDC`);
    console.log(`Small Donor 1: ${await this.getBalance(this.testAccounts[3].address)} USDC`);
    console.log(`Small Donor 2: ${await this.getBalance(this.testAccounts[4].address)} USDC\n`);

    // 2. Demonstrate donations
    console.log("💸 Processing donations...");
    await this.donate(50000, 2); // Major donor: 50k USDC
    await this.donate(5000, 3);  // Small donor 1: 5k USDC
    await this.donate(3000, 4);  // Small donor 2: 3k USDC

    console.log("\n📈 Fund Status After Donations:");
    console.log(await this.getContractState());

    // 3. Start streaming
    console.log("\n🌊 Initiating fund streaming...");
    await this.startStreaming();
    
    // 4. Show stream details
    console.log("\n🔍 Stream Details:");
    for (let i = 0; i < 2; i++) {
      const recipient = await this.contract.recipients(i);
      if (recipient.streamId.toString() !== "0") {
        const stream = await this.sablier.getStream(recipient.streamId);
        console.log(`\nCharity ${i === 0 ? 'A' : 'B'}:`);
        console.log(`- Total Amount: ${this.fmt(stream.amounts.deposited)} USDC`);
        console.log(`- Start Time: ${new Date(stream.startTime * 1000).toLocaleString()}`);
        console.log(`- End Time: ${new Date(stream.endTime * 1000).toLocaleString()}`);
      }
    }

    // 5. Simulate time passing and demonstrate voting
    console.log("\n🗳️ Simulating donor voting...");
    await this.vote(2); // Major donor votes
    console.log("Major donor voted to cancel");
    await this.vote(3); // Small donor 1 votes
    console.log("Small donor 1 voted to cancel");

    // 6. Show final state
    console.log("\n🏁 Final Fund Status:");
    const finalState = await this.getContractState();
    console.log(finalState);

    console.log("\n📊 Final USDC Balances:");
    console.log("Charities:");
    console.log(`Charity A: ${await this.getBalance(this.testAccounts[0].address)} USDC`);
    console.log(`Charity B: ${await this.getBalance(this.testAccounts[1].address)} USDC`);
    console.log("\nDonors:");
    console.log(`Major Donor: ${await this.getBalance(this.testAccounts[2].address)} USDC`);
    console.log(`Small Donor 1: ${await this.getBalance(this.testAccounts[3].address)} USDC`);
    console.log(`Small Donor 2: ${await this.getBalance(this.testAccounts[4].address)} USDC`);

    console.log("\n✨ Demonstration Complete!");
  }

  // Existing helper methods...
  async donate(amount, accountIndex = 2) {
    const donor = this.testAccounts[accountIndex];
    const donationAmount = this.parse(amount);

    await this.stablecoin.connect(donor).approve(this.contract.address, donationAmount);
    await this.contract.connect(donor).donate(donationAmount);
    
    console.log(`Processed ${amount} USDC donation from ${accountIndex === 2 ? 'Major Donor' : `Small Donor ${accountIndex-2}`}`);
  }

  async startStreaming() {
    await this.contract.startStreaming();
    return this.getContractState();
  }

  async vote(accountIndex) {
    await this.contract.connect(this.testAccounts[accountIndex]).vote();
  }

  async getContractState() {
    const [totalRaised, isStreaming, isCancelled] = await Promise.all([
      this.contract.totalRaised(),
      this.contract.isStreaming(),
      this.contract.isCancelled()
    ]);

    return {
      totalRaised: `${this.fmt(totalRaised)} USDC`,
      isStreaming,
      isCancelled
    };
  }

  async getBalance(address) {
    return this.fmt(await this.stablecoin.balanceOf(address));
  }
}

async function main() {
  const repl = await new GoFundMeREPL().initialize();
  
  // Run the demonstration
  await repl.demonstrateFullFlow();
  
  // Add to global scope for manual interaction
  global.repl = repl;
  global.ethers = ethers;
  
  console.log(`
    🛠️ REPL Ready for Manual Testing 🛠️
    
    Available commands:
    await repl.donate(amount, accountIndex)
    await repl.startStreaming()
    await repl.vote(accountIndex)
    await repl.getBalance(address)
    await repl.getContractState()
    await repl.demonstrateFullFlow()  // Run full demo again
  `);

  process.stdin.resume();
}

if (require.main === module) {
  main().catch(console.error);
}

module.exports = { GoFundMeREPL };