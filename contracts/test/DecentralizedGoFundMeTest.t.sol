// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../DecentralizedGoFundMe.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@sablier/contracts/sablier/ISablierV2LockupLinear.sol";
contract DecentralizedGoFundMeTest is Test {
    DecentralizedGoFundMe public gofundme;
    IERC20 public usdc;
    ISablierV2LockupLinear public sablier;
    
    address public admin;
    address public charityA;
    address public charityB;
    address public majorDonor;
    address public smallDonor1;
    address public smallDonor2;
    
    // Mainnet contract addresses
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant SABLIER = 0xAFb979d9afAd1aD27C5eFf4E27226E3AB9e5dCC9;
    
    function setUp() public {
        // Fork mainnet
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        
        // Setup accounts
        admin = makeAddr("admin");
        charityA = makeAddr("charityA");
        charityB = makeAddr("charityB");
        majorDonor = makeAddr("majorDonor");
        smallDonor1 = makeAddr("smallDonor1");
        smallDonor2 = makeAddr("smallDonor2");
        
        // Setup contract instances
        usdc = IERC20(USDC);
        sablier = ISablierV2LockupLinear(SABLIER);
        
        // Fund accounts with ETH
        vm.deal(admin, 100 ether);
        vm.deal(majorDonor, 100 ether);
        vm.deal(smallDonor1, 100 ether);
        vm.deal(smallDonor2, 100 ether);
        
        // Fund accounts with USDC
        deal(address(usdc), majorDonor, 100_000 * 1e6);
        deal(address(usdc), smallDonor1, 10_000 * 1e6);
        deal(address(usdc), smallDonor2, 10_000 * 1e6);
        
        // Deploy contract
        address[] memory recipients = new address[](2);
        recipients[0] = charityA;
        recipients[1] = charityB;
        
        uint256[] memory allocations = new uint256[](2);
        allocations[0] = 5000; // 50%
        allocations[1] = 5000; // 50%
        
        vm.startPrank(admin);
        gofundme = new DecentralizedGoFundMe(
            address(usdc),
            admin,
            address(sablier),
            recipients,
            allocations
        );
        vm.stopPrank();
    }

    function testFullDonationFlow() public {
        // Initial balances
        assertEq(usdc.balanceOf(majorDonor), 100_000 * 1e6);
        assertEq(usdc.balanceOf(smallDonor1), 10_000 * 1e6);
        assertEq(usdc.balanceOf(smallDonor2), 10_000 * 1e6);
        
        // Process donations
        vm.startPrank(majorDonor);
        usdc.approve(address(gofundme), 50_000 * 1e6);
        gofundme.donate(50_000 * 1e6);
        vm.stopPrank();
        
        vm.startPrank(smallDonor1);
        usdc.approve(address(gofundme), 5_000 * 1e6);
        gofundme.donate(5_000 * 1e6);
        vm.stopPrank();
        
        vm.startPrank(smallDonor2);
        usdc.approve(address(gofundme), 3_000 * 1e6);
        gofundme.donate(3_000 * 1e6);
        vm.stopPrank();
        
        // Verify total raised
        assertEq(gofundme.totalRaised(), 58_000 * 1e6);
        
        // Start streaming
        vm.prank(admin);
        gofundme.startStreaming();
        
        assertTrue(gofundme.isStreaming());
        
        // Test voting
        vm.prank(majorDonor);
        gofundme.vote();
        
        vm.prank(smallDonor1);
        gofundme.vote();
        
        // Verify cancellation (should happen since majority voted)
        assertTrue(gofundme.isCancelled());
    }
    
    function testDonationWeights() public {
        // Process donations
        vm.startPrank(majorDonor);
        usdc.approve(address(gofundme), 50_000 * 1e6);
        gofundme.donate(50_000 * 1e6);
        vm.stopPrank();
        
        vm.startPrank(smallDonor1);
        usdc.approve(address(gofundme), 5_000 * 1e6);
        gofundme.donate(5_000 * 1e6);
        vm.stopPrank();
        
        // Major donor should have majority voting power
        uint256 majorDonorWeight = gofundme.getVotingWeight(majorDonor);
        uint256 smallDonorWeight = gofundme.getVotingWeight(smallDonor1);
        
        assertTrue(majorDonorWeight > smallDonorWeight);
        assertEq(majorDonorWeight + smallDonorWeight, 10000); // Base 10000 for percentage
    }
    
    function testStreamCancellationAndRefunds() public {
        // Setup donations
        vm.startPrank(majorDonor);
        usdc.approve(address(gofundme), 50_000 * 1e6);
        gofundme.donate(50_000 * 1e6);
        vm.stopPrank();
        
        // Start streaming
        vm.prank(admin);
        gofundme.startStreaming();
        
        // Record balances before cancellation
        uint256 majorDonorBalanceBefore = usdc.balanceOf(majorDonor);
        
        // Cancel stream
        vm.prank(majorDonor);
        gofundme.vote();
        
        // Verify refund
        uint256 majorDonorBalanceAfter = usdc.balanceOf(majorDonor);
        assertTrue(majorDonorBalanceAfter > majorDonorBalanceBefore);
    }
    
    function testFailDoubleVote() public {
        vm.startPrank(majorDonor);
        usdc.approve(address(gofundme), 50_000 * 1e6);
        gofundme.donate(50_000 * 1e6);
        gofundme.vote();
        gofundme.vote(); // Should revert
        vm.stopPrank();
    }
    
    function testFailDonateAfterStreamingStarts() public {
        vm.prank(admin);
        gofundme.startStreaming();
        
        vm.startPrank(majorDonor);
        usdc.approve(address(gofundme), 50_000 * 1e6);
        gofundme.donate(50_000 * 1e6); // Should revert
        vm.stopPrank();
    }
}