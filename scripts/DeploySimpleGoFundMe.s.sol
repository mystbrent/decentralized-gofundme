// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../SimpleGoFundMe.sol";
import "../UniversityRegistry.sol";

contract DeploySimpleGoFundMe is Script {
    // Configuration - using Sepolia USDC for example
    address constant USDC = 0xda9d4f9b69ac6C22e444eD9aF0CfC043b7a7f53f;
    address public platformWallet;
    
    function setUp() public {
        // Set platform wallet to script runner
        platformWallet = msg.sender;
    }

    function run() public {
        // Get private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy University Registry
        UniversityRegistry registry = new UniversityRegistry(msg.sender);
        console.log("UniversityRegistry deployed at:", address(registry));

        // 2. Add Universities (using msg.sender as placeholder - replace with real addresses)
        registry.addUniversity("UNI_A", "University A", msg.sender);
        registry.addUniversity("UNI_B", "University B", msg.sender);
        console.log("Universities added to registry");

        // 3. Setup GoFundMe parameters
        string[] memory universities = new string[](2);
        universities[0] = "UNI_A";
        universities[1] = "UNI_B";

        uint256[] memory allocations = new uint256[](2);
        allocations[0] = 5000; // 50%
        allocations[1] = 5000; // 50%

        // 4. Deploy GoFundMe
        SimpleGoFundMe gofundme = new SimpleGoFundMe(
            USDC,
            platformWallet,
            address(registry),
            universities,
            allocations
        );
        console.log("SimpleGoFundMe deployed at:", address(gofundme));

        vm.stopBroadcast();
    }
}