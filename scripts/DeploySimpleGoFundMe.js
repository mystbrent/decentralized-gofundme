const { ethers } = require("hardhat");

async function main() {
  console.log("Starting deployment...");
  
  // Get the deployer account
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);

  // Get contract factories
  const UniversityRegistry = await ethers.getContractFactory("UniversityRegistry");
  const SimpleGoFundMe = await ethers.getContractFactory("SimpleGoFundMe");

  // Deploy UniversityRegistry
  console.log("Deploying UniversityRegistry...");
  const registry = await UniversityRegistry.deploy(deployer.address);
  await registry.waitForDeployment();
  console.log("UniversityRegistry deployed to:", await registry.getAddress());

  // Add universities
  console.log("Adding universities to registry...");
  await registry.addUniversity("UNI_A", "University A", '0x24395Aa780aC377D57DF79d6cDdA7f29af6586Ef');
  await registry.addUniversity("UNI_B", "University B", '0x8b3a46E088524A69db8aF4835e69c1CBA81e9155');
  console.log("Universities added");

  // Setup GoFundMe parameters
  const USDC_ADDRESS = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"; // ETH USDC
  const platformWallet = deployer.address;
  const universities = ["UNI_A", "UNI_B"];
  const allocations = [5000, 5000]; // 50% each

  // Deploy SimpleGoFundMe
  console.log("Deploying SimpleGoFundMe...");
  const gofundme = await SimpleGoFundMe.deploy(
    USDC_ADDRESS,
    platformWallet,
    await registry.getAddress(),
    universities,
    allocations
  );
  await gofundme.waitForDeployment();
  console.log("SimpleGoFundMe deployed to:", await gofundme.getAddress());

  // Verify contracts on Etherscan
  if (process.env.ETHERSCAN_API_KEY) {
    console.log("Verifying contracts on Etherscan...");
    await hre.run("verify:verify", {
      address: await registry.getAddress(),
      constructorArguments: [deployer.address],
    });

    await hre.run("verify:verify", {
      address: await gofundme.getAddress(),
      constructorArguments: [
        USDC_ADDRESS,
        platformWallet,
        await registry.getAddress(),
        universities,
        allocations,
      ],
    });
  }

  console.log("Deployment complete!");
  return { registry, gofundme };
}

// For REPL usage
async function deploy() {
  const contracts = await main();
  return contracts;
}

// Execute if running directly
if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
}

module.exports = { deploy };