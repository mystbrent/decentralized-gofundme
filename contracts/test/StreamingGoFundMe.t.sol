// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../StreamingGoFundMe.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@sablier/contracts/sablier/ISablierV2LockupLinear.sol";

contract StreamingGoFundMeTest is Test {
    StreamingGoFundMe public gofundme;
    IERC20 public usdc;
    
    address public admin = address(1);
    address public charityA = address(2);
    address public charityB = address(3);
    address public donor = address(4);
    
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant SABLIER = 0xAFb979d9afAd1aD27C5eFf4E27226E3AB9e5dCC9;
    
    uint256 constant DONATION_AMOUNT = 1000 * 1e6; // 1000 USDC
    
    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        
        vm.startPrank(admin);
        
        // Setup recipients
        address[] memory recipients = new address[](2);
        recipients[0] = charityA;
        recipients[1] = charityB;
        
        uint256[] memory allocations = new uint256[](2);
        allocations[0] = 5000; // 50%
        allocations[1] = 5000; // 50%
        
        // Deploy contract
        gofundme = new StreamingGoFundMe(
            USDC,
            admin,
            SABLIER,
            recipients,
            allocations
        );
        
        usdc = IERC20(USDC);
        
        // Fund donor
        deal(address(usdc), donor, DONATION_AMOUNT);
        
        vm.stopPrank();
    }

    function testBasicDonation() public {
        vm.startPrank(donor);
        
        // Approve and donate
        usdc.approve(address(gofundme), DONATION_AMOUNT);
        gofundme.donate(DONATION_AMOUNT);
        
        // Basic checks
        assertEq(gofundme.totalRaised(), DONATION_AMOUNT);
        
        vm.stopPrank();
    }

    function testStartStreaming() public {
        // Make donation first
        vm.startPrank(donor);
        usdc.approve(address(gofundme), DONATION_AMOUNT);
        gofundme.donate(DONATION_AMOUNT);
        vm.stopPrank();
        
        // Start streaming
        vm.startPrank(admin);
        gofundme.startStreaming();
        vm.stopPrank();
        
        // Verify streaming started
        assertTrue(gofundme.isStreaming());
    }
}