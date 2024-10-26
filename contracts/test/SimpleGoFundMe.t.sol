// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../SimpleGoFundMe.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SimpleGoFundMeTest is Test {
    SimpleGoFundMe public gofundme;
    IERC20 public usdc;

    address public admin;
    address public charityA;
    address public charityB;
    address public majorDonor;
    address public smallDonor1;
    address public smallDonor2;

    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    uint256 constant MAJOR_DONOR_AMOUNT = 100_000 * 1e6; // 100,000 USDC
    uint256 constant SMALL_DONOR_AMOUNT = 10_000 * 1e6; // 10,000 USDC
    uint256 constant MAJOR_DONATION = 50_000 * 1e6; // 50,000 USDC
    uint256 constant SMALL_DONATION_1 = 5_000 * 1e6; // 5,000 USDC
    uint256 constant SMALL_DONATION_2 = 3_000 * 1e6; // 3,000 USDC

    function formatUSDC(uint256 amount) internal pure returns (string memory) {
        return string(abi.encodePacked(vm.toString(amount / 1e6), " USDC"));
    }

    function setUp() public {
        console.log("Initializing GoFundMe Test Environment...\n");

        // Fork mainnet
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), 19_000_000);
        console.log("Forked Mainnet at block 19,000,000\n");

        // Setup addresses
        admin = makeAddr("admin");
        charityA = makeAddr("charityA");
        charityB = makeAddr("charityB");
        majorDonor = makeAddr("majorDonor");
        smallDonor1 = makeAddr("smallDonor1");
        smallDonor2 = makeAddr("smallDonor2");

        console.log("Test Accounts:");
        console.log("Admin:", admin);
        console.log("Charity A:", charityA);
        console.log("Charity B:", charityB);
        console.log("Major Donor:", majorDonor);
        console.log("Small Donor 1:", smallDonor1);
        console.log("Small Donor 2:", smallDonor2);

        vm.startPrank(admin);

        // Setup USDC
        usdc = IERC20(USDC);

        // Fund test accounts
        deal(address(usdc), majorDonor, MAJOR_DONOR_AMOUNT);
        deal(address(usdc), smallDonor1, SMALL_DONOR_AMOUNT);
        deal(address(usdc), smallDonor2, SMALL_DONOR_AMOUNT);

        console.log("\nInitial Balances:");
        console.log("Major Donor:", formatUSDC(usdc.balanceOf(majorDonor)));
        console.log("Small Donor 1:", formatUSDC(usdc.balanceOf(smallDonor1)));
        console.log("Small Donor 2:", formatUSDC(usdc.balanceOf(smallDonor2)));

        // Deploy contract
        address[] memory recipients = new address[](2);
        recipients[0] = charityA;
        recipients[1] = charityB;

        uint256[] memory allocations = new uint256[](2);
        allocations[0] = 5000; // 50%
        allocations[1] = 5000; // 50%

        console.log("\nDeploying GoFundMe contract...");
        gofundme = new SimpleGoFundMe(
            address(usdc),
            admin,
            recipients,
            allocations
        );
        console.log("Contract deployed at:", address(gofundme));

        vm.stopPrank();
    }

    function testBasicDonation() public {
        console.log("\nTesting Basic Donation Flow");

        vm.startPrank(majorDonor);
        usdc.approve(address(gofundme), MAJOR_DONATION);
        gofundme.donate(MAJOR_DONATION);
        vm.stopPrank();

        assertEq(
            gofundme.totalRaised(),
            MAJOR_DONATION,
            "Total raised should match donation"
        );
        assertEq(
            usdc.balanceOf(address(gofundme)),
            MAJOR_DONATION,
            "Contract balance should match donation"
        );
    }

    function testFullFundingFlow() public {
        console.log("\nTesting Full Funding Flow");

        // Process donations
        vm.startPrank(majorDonor);
        usdc.approve(address(gofundme), MAJOR_DONATION);
        gofundme.donate(MAJOR_DONATION);
        vm.stopPrank();

        vm.startPrank(smallDonor1);
        usdc.approve(address(gofundme), SMALL_DONATION_1);
        gofundme.donate(SMALL_DONATION_1);
        vm.stopPrank();

        vm.startPrank(smallDonor2);
        usdc.approve(address(gofundme), SMALL_DONATION_2);
        gofundme.donate(SMALL_DONATION_2);
        vm.stopPrank();

        uint256 totalDonations = MAJOR_DONATION +
            SMALL_DONATION_1 +
            SMALL_DONATION_2;
        assertEq(
            gofundme.totalRaised(),
            totalDonations,
            "Total raised mismatch"
        );

        // Record initial balances
        uint256 initialCharityABalance = usdc.balanceOf(charityA);
        uint256 initialCharityBBalance = usdc.balanceOf(charityB);
        uint256 initialAdminBalance = usdc.balanceOf(admin);

        // Start funding
        vm.startPrank(admin);
        gofundme.startFunding();
        vm.stopPrank();

        // Calculate expected amounts with new distribution logic
        uint256 platformFee = (totalDonations * 100) / 10000; // 1%
        uint256 remainingAfterFee = totalDonations - platformFee;
        uint256 toDistribute = (remainingAfterFee * 7000) / 10000; // 70% for initial distribution
        uint256 toReserve = remainingAfterFee - toDistribute; // 30% kept in reserve
        uint256 expectedPerCharity = toDistribute / 2; // 50% each of the distributable amount

        console.log("\nExpected Distribution:");
        console.log("Total Donations:", formatUSDC(totalDonations));
        console.log("Platform Fee:", formatUSDC(platformFee));
        console.log("To Distribute:", formatUSDC(toDistribute));
        console.log("To Reserve:", formatUSDC(toReserve));
        console.log("Per Charity:", formatUSDC(expectedPerCharity));

        // Verify balances
        console.log("\nVerifying Final Balances:");

        uint256 actualCharityAReceived = usdc.balanceOf(charityA) -
            initialCharityABalance;
        uint256 actualCharityBReceived = usdc.balanceOf(charityB) -
            initialCharityBBalance;
        uint256 actualPlatformFee = usdc.balanceOf(admin) - initialAdminBalance;
        uint256 contractBalance = usdc.balanceOf(address(gofundme));

        console.log("Charity A received:", formatUSDC(actualCharityAReceived));
        console.log("Charity B received:", formatUSDC(actualCharityBReceived));
        console.log("Platform fee:", formatUSDC(actualPlatformFee));
        console.log("Contract reserve:", formatUSDC(contractBalance));

        // Assert the correct amounts were distributed
        assertEq(
            actualCharityAReceived,
            expectedPerCharity,
            "Charity A received incorrect amount"
        );
        assertEq(
            actualCharityBReceived,
            expectedPerCharity,
            "Charity B received incorrect amount"
        );
        assertEq(actualPlatformFee, platformFee, "Platform fee incorrect");
        assertEq(contractBalance, toReserve, "Incorrect reserve amount");

        assertTrue(gofundme.isActive(), "Funding should be active");
    }

    // Also update testFundingCancellation to be more explicit about amounts
    function testFundingCancellation() public {
        console.log("\nTesting Funding Cancellation Flow");

        // Major donor donates and funding starts
        vm.startPrank(majorDonor);
        usdc.approve(address(gofundme), MAJOR_DONATION);
        gofundme.donate(MAJOR_DONATION);
        vm.stopPrank();

        uint256 initialDonorBalance = usdc.balanceOf(majorDonor);

        vm.startPrank(admin);
        gofundme.startFunding();
        vm.stopPrank();

        // Calculate expected reserve amount
        uint256 platformFee = (MAJOR_DONATION * 100) / 10000; // 1%
        uint256 remainingAfterFee = MAJOR_DONATION - platformFee;
        uint256 expectedReserve = (remainingAfterFee * 3000) / 10000; // 30% reserve

        // Verify reserve amount before cancellation
        uint256 contractBalance = usdc.balanceOf(address(gofundme));
        assertEq(contractBalance, expectedReserve, "Incorrect reserve amount");

        console.log("\nBefore cancellation:");
        console.log("Contract reserve:", formatUSDC(contractBalance));

        // Major donor votes to cancel
        vm.startPrank(majorDonor);
        gofundme.vote();
        vm.stopPrank();

        uint256 finalDonorBalance = usdc.balanceOf(majorDonor);
        uint256 refundReceived = finalDonorBalance - initialDonorBalance;

        console.log("\nAfter cancellation:");
        console.log("Refund received:", formatUSDC(refundReceived));
        console.log(
            "Contract balance:",
            formatUSDC(usdc.balanceOf(address(gofundme)))
        );

        assertTrue(gofundme.isCancelled(), "Funding should be cancelled");
        assertFalse(gofundme.isActive(), "Funding should not be active");
        assertEq(
            refundReceived,
            expectedReserve,
            "Donor should receive full reserve amount"
        );
        assertEq(
            usdc.balanceOf(address(gofundme)),
            0,
            "Contract should have no remaining balance"
        );
    }

    function testFailDoubleStart() public {
        vm.startPrank(majorDonor);
        usdc.approve(address(gofundme), MAJOR_DONATION);
        gofundme.donate(MAJOR_DONATION);
        vm.stopPrank();

        vm.startPrank(admin);
        gofundme.startFunding();
        gofundme.startFunding(); // Should fail
        vm.stopPrank();
    }

    function testFailDoubleVote() public {
        vm.startPrank(majorDonor);
        usdc.approve(address(gofundme), MAJOR_DONATION);
        gofundme.donate(MAJOR_DONATION);
        vm.stopPrank();

        vm.startPrank(admin);
        gofundme.startFunding();
        vm.stopPrank();

        vm.startPrank(majorDonor);
        gofundme.vote();
        gofundme.vote(); // Should fail
        vm.stopPrank();
    }
}
