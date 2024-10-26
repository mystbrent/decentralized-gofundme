// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../DecentralizedGoFundMe.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@sablier/contracts/sablier/ISablierV2LockupLinear.sol";
import "@sablier/contracts/sablier/DataTypes.sol";

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
    
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant SABLIER = 0xAFb979d9afAd1aD27C5eFf4E27226E3AB9e5dCC9;
    
    uint256 constant MAJOR_DONOR_AMOUNT = 100_000 * 1e6;
    uint256 constant SMALL_DONOR_AMOUNT = 10_000 * 1e6;
    uint256 constant MAJOR_DONATION = 50_000 * 1e6;
    uint256 constant SMALL_DONATION_1 = 5_000 * 1e6;
    uint256 constant SMALL_DONATION_2 = 3_000 * 1e6;

    function formatUSDC(uint256 amount) internal pure returns (string memory) {
        return string(abi.encodePacked(vm.toString(amount / 1e6), " USDC"));
    }
    
    function setUp() public {
        console.log("Initializing GoFundMe Test Environment...\n");
        
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), 19_000_000);
        console.log("Forked Mainnet at block 19,000,000\n");
        
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
        
        usdc = IERC20(USDC);
        sablier = ISablierV2LockupLinear(SABLIER);
        
        // Fund accounts
        vm.deal(admin, 100 ether);
        vm.deal(majorDonor, 100 ether);
        vm.deal(smallDonor1, 100 ether);
        vm.deal(smallDonor2, 100 ether);
        
        deal(address(usdc), majorDonor, MAJOR_DONOR_AMOUNT);
        deal(address(usdc), smallDonor1, SMALL_DONOR_AMOUNT);
        deal(address(usdc), smallDonor2, SMALL_DONOR_AMOUNT);

        console.log("\n Initial Balances:");
        console.log("Major Donor:", formatUSDC(usdc.balanceOf(majorDonor)));
        console.log("Small Donor 1:", formatUSDC(usdc.balanceOf(smallDonor1)));
        console.log("Small Donor 2:", formatUSDC(usdc.balanceOf(smallDonor2)));
        
        address[] memory recipients = new address[](2);
        recipients[0] = charityA;
        recipients[1] = charityB;
        
        uint256[] memory allocations = new uint256[](2);
        allocations[0] = 5000;
        allocations[1] = 5000;

        console.log("\n Deploying GoFundMe contract...");
        
        gofundme = new DecentralizedGoFundMe(
            address(usdc),
            admin,
            address(sablier),
            recipients,
            allocations
        );
        
        console.log("Contract deployed at:", address(gofundme));
        vm.stopPrank();
    }

    function testFullFundingFlow() public {
        console.log("\n Starting Full Funding Flow Test\n");

        // Initial balances
        console.log(" Initial Balances:");
        console.log("Major Donor:", formatUSDC(usdc.balanceOf(majorDonor)));
        console.log("Small Donor 1:", formatUSDC(usdc.balanceOf(smallDonor1)));
        console.log("Small Donor 2:", formatUSDC(usdc.balanceOf(smallDonor2)));
        
        console.log("\n Processing donations...");
        
        vm.startPrank(majorDonor);
        usdc.approve(address(gofundme), MAJOR_DONATION);
        gofundme.donate(MAJOR_DONATION);
        console.log("Major Donor donated:", formatUSDC(MAJOR_DONATION));
        vm.stopPrank();
        
        vm.startPrank(smallDonor1);
        usdc.approve(address(gofundme), SMALL_DONATION_1);
        gofundme.donate(SMALL_DONATION_1);
        console.log("Small Donor 1 donated:", formatUSDC(SMALL_DONATION_1));
        vm.stopPrank();
        
        vm.startPrank(smallDonor2);
        usdc.approve(address(gofundme), SMALL_DONATION_2);
        gofundme.donate(SMALL_DONATION_2);
        console.log("Small Donor 2 donated:", formatUSDC(SMALL_DONATION_2));
        vm.stopPrank();
        
        uint256 expectedTotal = MAJOR_DONATION + SMALL_DONATION_1 + SMALL_DONATION_2;
        console.log("\n Total Raised:", formatUSDC(gofundme.totalRaised()));
        assertEq(gofundme.totalRaised(), expectedTotal, "Total raised mismatch");
        
        console.log("\n Starting fund streaming...");
        vm.startPrank(admin);
        try gofundme.startStreaming() {
            console.log("Streaming started successfully");
        } catch Error(string memory reason) {
            console.log("Failed to start streaming:", reason);
            revert("Stream start failed");
        }
        vm.stopPrank();
        
        assertTrue(gofundme.isStreaming(), "Streaming should be active");
        
        (,, uint256 streamIdA) = gofundme.recipients(0);
        (,, uint256 streamIdB) = gofundme.recipients(1);
        
        console.log("\n Stream Details:");
        console.log("Charity A Stream ID:", streamIdA);
        console.log("Charity B Stream ID:", streamIdB);
        
        // Verify stream details
        LockupLinear.StreamLL memory streamA = sablier.getStream(streamIdA);
        LockupLinear.StreamLL memory streamB = sablier.getStream(streamIdB);
        
        uint256 totalAfterFee = expectedTotal * 9900 / 10000;
        uint256 expectedPerCharity = totalAfterFee / 2;
        
        console.log("\n Stream Amounts:");
        console.log("Expected per charity:", formatUSDC(expectedPerCharity));
        console.log("Actual Stream A:", formatUSDC(uint256(streamA.amounts.deposited)));
        console.log("Actual Stream B:", formatUSDC(uint256(streamB.amounts.deposited)));
        
        // Time progression
        console.log("\n Fast forwarding 15 days...");
        vm.warp(block.timestamp + 15 days);
        
        // Voting
        console.log("\n Testing voting mechanism...");
        vm.startPrank(majorDonor);
        try gofundme.vote() {
            console.log("Major donor voted successfully");
        } catch Error(string memory reason) {
            console.log("Vote failed:", reason);
            revert("Voting failed");
        }
        vm.stopPrank();
        
        uint256 majorDonorWeight = gofundme.getVotingWeight(majorDonor);
        console.log("Major donor voting weight:", majorDonorWeight);
        
        assertTrue(gofundme.isCancelled(), "Stream should be cancelled");
        assertFalse(gofundme.isStreaming(), "Streaming should be stopped");
        
        console.log("\n Final Balances:");
        console.log("Major Donor:", formatUSDC(usdc.balanceOf(majorDonor)));
        console.log("Small Donor 1:", formatUSDC(usdc.balanceOf(smallDonor1)));
        console.log("Small Donor 2:", formatUSDC(usdc.balanceOf(smallDonor2)));
        console.log("Charity A:", formatUSDC(usdc.balanceOf(charityA)));
        console.log("Charity B:", formatUSDC(usdc.balanceOf(charityB)));
        
        console.log("\n Full funding flow test completed");
    }

    function testStreamCancellationRefunds() public {
        console.log("\n Starting Stream Cancellation Test\n");

        console.log(" Processing major donor donation...");
        vm.startPrank(majorDonor);
        usdc.approve(address(gofundme), MAJOR_DONATION);
        gofundme.donate(MAJOR_DONATION);
        vm.stopPrank();
        
        console.log("\n Starting streaming...");
        vm.startPrank(admin);
        try gofundme.startStreaming() {
            console.log("Streaming started successfully");
        } catch Error(string memory reason) {
            console.log("Failed to start streaming:", reason);
            revert("Stream start failed");
        }
        vm.stopPrank();
        
        uint256 initialDonorBalance = usdc.balanceOf(majorDonor);
        uint256 initialCharityABalance = usdc.balanceOf(charityA);
        uint256 initialCharityBBalance = usdc.balanceOf(charityB);

        console.log("\n Initial Balances:");
        console.log("Major Donor:", formatUSDC(initialDonorBalance));
        console.log("Charity A:", formatUSDC(initialCharityABalance));
        console.log("Charity B:", formatUSDC(initialCharityBBalance));
        
        console.log("\n Fast forwarding 3 days...");
        vm.warp(block.timestamp + 3 days);
        
        console.log("\n Major donor voting to cancel...");
        vm.startPrank(majorDonor);
        try gofundme.vote() {
            console.log("Vote successful");
        } catch Error(string memory reason) {
            console.log("Vote failed:", reason);
            revert("Voting failed");
        }
        vm.stopPrank();

        uint256 finalDonorBalance = usdc.balanceOf(majorDonor);
        uint256 finalCharityABalance = usdc.balanceOf(charityA);
        uint256 finalCharityBBalance = usdc.balanceOf(charityB);

        console.log("\n Final Balances:");
        console.log("Major Donor:", formatUSDC(finalDonorBalance));
        console.log("Charity A:", formatUSDC(finalCharityABalance));
        console.log("Charity B:", formatUSDC(finalCharityBBalance));
        
        assertTrue(finalDonorBalance > initialDonorBalance, "Donor should receive refund");
        assertTrue(finalCharityABalance > initialCharityABalance, "Charity A should receive partial funds");
        assertTrue(finalCharityBBalance > initialCharityBBalance, "Charity B should receive partial funds");
        
        console.log("\n Stream cancellation test completed");
    }
}