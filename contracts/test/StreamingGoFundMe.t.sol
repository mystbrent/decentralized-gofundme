// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../StreamingGoFundMe.sol";
import "../UniversityRegistry.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@sablier/contracts/sablier/ISablierV2LockupLinear.sol";

contract StreamingGoFundMeTest is Test {
    StreamingGoFundMe public gofundme;
    UniversityRegistry public registry;
    IERC20 public usdc;
    
    address public admin = address(1);
    address public uniA = address(2);
    address public uniB = address(3);
    address public donor = address(4);
    
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant SABLIER = 0xAFb979d9afAd1aD27C5eFf4E27226E3AB9e5dCC9;
    
    uint256 constant DONATION_AMOUNT = 1000 * 1e6; // 1000 USDC
    
    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        
        vm.startPrank(admin);
        
        // Deploy registry and add universities
        registry = new UniversityRegistry(admin);
        registry.addUniversity("UNI_A", "University A", uniA);
        registry.addUniversity("UNI_B", "University B", uniB);
        
        string[] memory symbols = new string[](2);
        symbols[0] = "UNI_A";
        symbols[1] = "UNI_B";
        
        uint256[] memory allocations = new uint256[](2);
        allocations[0] = 5000; // 50%
        allocations[1] = 5000; // 50%
        
        // Deploy main contract
        gofundme = new StreamingGoFundMe(
            USDC,
            admin,
            address(registry),
            SABLIER,
            symbols,
            allocations
        );
        
        usdc = IERC20(USDC);
        
        // Fund donor
        deal(address(usdc), donor, DONATION_AMOUNT);
        
        vm.stopPrank();
    }

    function testDonationAndStreaming() public {
        vm.startPrank(donor);
        usdc.approve(address(gofundme), DONATION_AMOUNT);
        gofundme.donate(DONATION_AMOUNT);
        assertEq(gofundme.totalRaised(), DONATION_AMOUNT);
        vm.stopPrank();
        
        vm.startPrank(admin);
        gofundme.startStreaming();
        assertTrue(gofundme.isStreaming());
        vm.stopPrank();
    }

    function testInvalidUniversity() public {
        vm.startPrank(admin);
        
        string[] memory symbols = new string[](1);
        symbols[0] = "INVALID_UNI";
        
        uint256[] memory allocations = new uint256[](1);
        allocations[0] = 10000;
        
        vm.expectRevert();
        new StreamingGoFundMe(
            USDC,
            admin,
            address(registry),
            SABLIER,
            symbols,
            allocations
        );
        
        vm.stopPrank();
    }
}