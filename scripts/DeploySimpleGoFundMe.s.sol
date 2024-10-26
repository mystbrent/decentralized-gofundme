// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/SimpleGoFundMe.sol";
import "../src/UniversityRegistry.sol";

contract DeploySimpleGoFundMe is Script {
    // Configuration
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public platformWallet;

    function setUp() public {
        // Set platform wallet to script runner
        platformWallet = msg.sender;
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy University Registry
        UniversityRegistry registry = new UniversityRegistry(msg.sender);
        console.log("UniversityRegistry deployed at:", address(registry));

        // 2. Add Universities
        registry.addUniversity("UNI_A", "University A", 0x1234...); // Replace with actual address
        registry.addUniversity("UNI_B", "University B", 0x5678...); // Replace with actual address
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