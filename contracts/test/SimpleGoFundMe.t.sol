// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../SimpleGoFundMe.sol";
import "../UniversityRegistry.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SimpleGoFundMeTest is Test {
    SimpleGoFundMe public gofundme;
    UniversityRegistry public registry;
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

    // University symbols
    string constant UNI_A = "UNI_A";
    string constant UNI_B = "UNI_B";

    function formatUSDC(uint256 amount) internal pure returns (string memory) {
        return string(abi.encodePacked(vm.toString(amount / 1e6), " USDC"));
    }

    function setUp() public {
        console.log("Initializing Test Environment...\n");

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
        console.log("University A:", charityA);
        console.log("University B:", charityB);
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

        // Deploy and setup UniversityRegistry
        console.log("\nDeploying UniversityRegistry...");
        registry = new UniversityRegistry(admin);

        console.log("Adding universities to registry:");
        registry.addUniversity(UNI_A, "University A", charityA);
        console.log("Added University A:", UNI_A);

        registry.addUniversity(UNI_B, "University B", charityB);
        console.log("Added University B:", UNI_B);

        // Verify universities were added correctly
        (string memory nameA, address walletA, bool isActiveA) = registry
            .getUniversity(UNI_A);
        (string memory nameB, address walletB, bool isActiveB) = registry
            .getUniversity(UNI_B);

        require(walletA == charityA && isActiveA, "University A setup failed");
        require(walletB == charityB && isActiveB, "University B setup failed");

        // Setup university symbols and allocations for GoFundMe
        string[] memory universities = new string[](2);
        universities[0] = UNI_A;
        universities[1] = UNI_B;

        uint256[] memory allocations = new uint256[](2);
        allocations[0] = 5000; // 50%
        allocations[1] = 5000; // 50%

        console.log("\nDeploying GoFundMe contract...");
        gofundme = new SimpleGoFundMe(
            address(usdc),
            admin,
            address(registry),
            universities,
            allocations
        );

        console.log("Contract deployed at:", address(gofundme));
        vm.stopPrank();
    }

    function testRegistrySetup() public {
        console.log("\nTesting Registry Setup");

        // Test university retrieval
        (string memory nameA, address walletA, bool isActiveA) = registry
            .getUniversity(UNI_A);
        (string memory nameB, address walletB, bool isActiveB) = registry
            .getUniversity(UNI_B);

        assertTrue(isActiveA, "University A should be active");
        assertTrue(isActiveB, "University B should be active");
        assertEq(walletA, charityA, "University A wallet mismatch");
        assertEq(walletB, charityB, "University B wallet mismatch");

        // Test wallet validation
        assertTrue(
            registry.isValidUniversityWallet(charityA),
            "Charity A should be valid"
        );
        assertTrue(
            registry.isValidUniversityWallet(charityB),
            "Charity B should be valid"
        );
        assertFalse(
            registry.isValidUniversityWallet(address(0x1)),
            "Random address should be invalid"
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

        // Calculate expected amounts
        uint256 platformFee = (totalDonations * 100) / 10000; // 1%
        uint256 remainingAfterFee = totalDonations - platformFee;
        uint256 toDistribute = (remainingAfterFee * 7000) / 10000; // 70% initial distribution
        uint256 expectedPerCharity = toDistribute / 2; // 50% each

        // Verify balances
        console.log("\nVerifying Final Balances:");

        uint256 actualCharityAReceived = usdc.balanceOf(charityA) -
            initialCharityABalance;
        uint256 actualCharityBReceived = usdc.balanceOf(charityB) -
            initialCharityBBalance;
        uint256 actualPlatformFee = usdc.balanceOf(admin) - initialAdminBalance;

        console.log(
            "University A received:",
            formatUSDC(actualCharityAReceived)
        );
        console.log(
            "University B received:",
            formatUSDC(actualCharityBReceived)
        );
        console.log("Platform fee:", formatUSDC(actualPlatformFee));

        assertEq(
            actualCharityAReceived,
            expectedPerCharity,
            "University A received incorrect amount"
        );
        assertEq(
            actualCharityBReceived,
            expectedPerCharity,
            "University B received incorrect amount"
        );
        assertEq(actualPlatformFee, platformFee, "Platform fee incorrect");
        assertTrue(gofundme.isActive(), "Funding should be active");
    }

    function testFundingCancellation() public {
        console.log("\nTesting Funding Cancellation Flow");

        vm.startPrank(majorDonor);
        usdc.approve(address(gofundme), MAJOR_DONATION);
        gofundme.donate(MAJOR_DONATION);
        vm.stopPrank();

        uint256 initialBalance = usdc.balanceOf(majorDonor);

        vm.startPrank(admin);
        gofundme.startFunding();
        vm.stopPrank();

        // Calculate expected reserve
        uint256 platformFee = (MAJOR_DONATION * 100) / 10000; // 1%
        uint256 remainingAfterFee = MAJOR_DONATION - platformFee;
        uint256 expectedReserve = (remainingAfterFee * 3000) / 10000; // 30% reserve

        uint256 contractBalance = usdc.balanceOf(address(gofundme));
        assertEq(contractBalance, expectedReserve, "Incorrect reserve amount");

        console.log("\nBefore cancellation:");
        console.log("Contract reserve:", formatUSDC(contractBalance));

        vm.startPrank(majorDonor);
        gofundme.vote();
        vm.stopPrank();

        uint256 finalBalance = usdc.balanceOf(majorDonor);
        uint256 refundReceived = finalBalance - initialBalance;

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

    function testFailInvalidUniversity() public {
        string[] memory universities = new string[](1);
        universities[0] = "INVALID_UNI";

        uint256[] memory allocations = new uint256[](1);
        allocations[0] = 10000;

        vm.startPrank(admin);
        // Should fail because university is not in registry
        new SimpleGoFundMe(
            address(usdc),
            admin,
            address(registry),
            universities,
            allocations
        );
        vm.stopPrank();
    }

    function testFailDeactivatedUniversity() public {
        vm.startPrank(admin);

        // Deactivate University A
        registry.deactivateUniversity(UNI_A);

        string[] memory universities = new string[](1);
        universities[0] = UNI_A;

        uint256[] memory allocations = new uint256[](1);
        allocations[0] = 10000;

        // Should fail because university is deactivated
        new SimpleGoFundMe(
            address(usdc),
            admin,
            address(registry),
            universities,
            allocations
        );
        vm.stopPrank();
    }
}
