// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract SimpleGoFundMe is ReentrancyGuard, Ownable {
    struct Recipient {
        address wallet;
        uint256 allocation;
    }

    struct Donor {
        uint256 amount;
        bool hasVoted;
    }

    uint256 private constant PLATFORM_FEE = 100; // 1%
    uint256 private constant VOTE_THRESHOLD = 5000; // 50%
    uint256 private constant INITIAL_DISTRIBUTION = 7000; // 70%
    uint256 private constant RESERVE_AMOUNT = 3000; // 30% kept in reserve

    IERC20 public immutable stablecoin;
    address public immutable platformWallet;

    mapping(address => Donor) public donors;
    address[] public donorList;
    Recipient[] public recipients;
    uint256 public totalRaised;
    uint256 public totalVotingWeight;
    bool public isActive;
    bool public isCancelled;

    event DonationReceived(address indexed donor, uint256 amount);
    event FundingStarted(uint256 totalAmount, uint256 distributed, uint256 reserved);
    event RecipientPaid(address indexed recipient, uint256 amount);
    event VoteCast(address indexed donor, uint256 weight);
    event FundsCancelled();
    event RefundIssued(address indexed donor, uint256 amount);

    constructor(
        address _stablecoin,
        address _platformWallet,
        address[] memory _recipients,
        uint256[] memory _allocations
    ) Ownable(msg.sender) {
        require(_recipients.length == _allocations.length, "Invalid recipients/allocations");
        require(_recipients.length > 0, "No recipients");

        stablecoin = IERC20(_stablecoin);
        platformWallet = _platformWallet;

        uint256 totalAllocation;
        for (uint i = 0; i < _recipients.length; i++) {
            require(_recipients[i] != address(0), "Invalid recipient");
            require(_allocations[i] > 0, "Invalid allocation");
            totalAllocation = totalAllocation + _allocations[i];
            recipients.push(Recipient({
                wallet: _recipients[i],
                allocation: _allocations[i]
            }));
        }
        require(totalAllocation == 10000, "Total allocation must be 100%");
    }

    function donate(uint256 amount) external nonReentrant {
        require(!isActive && !isCancelled, "Fund not accepting donations");
        require(amount > 0, "Invalid amount");

        stablecoin.transferFrom(msg.sender, address(this), amount);

        if (donors[msg.sender].amount == 0) {
            donorList.push(msg.sender);
        }
        donors[msg.sender].amount = donors[msg.sender].amount + amount;
        totalRaised = totalRaised + amount;

        emit DonationReceived(msg.sender, amount);
    }

    function startFunding() external onlyOwner nonReentrant {
        require(!isActive && !isCancelled, "Invalid state");
        require(totalRaised > 0, "No funds raised");

        uint256 platformFeeAmount = (totalRaised * PLATFORM_FEE) / 10000;
        uint256 remainingAfterFee = totalRaised - platformFeeAmount;
        
        // Calculate amounts for immediate distribution and reserve
        uint256 toDistribute = (remainingAfterFee * INITIAL_DISTRIBUTION) / 10000;
        uint256 toReserve = remainingAfterFee - toDistribute;

        // Send platform fee
        require(stablecoin.transfer(platformWallet, platformFeeAmount), "Platform fee transfer failed");
        
        // Distribute initial funds to recipients
        for (uint i = 0; i < recipients.length; i++) {
            uint256 amount = (toDistribute * recipients[i].allocation) / 10000;
            require(stablecoin.transfer(recipients[i].wallet, amount), "Recipient transfer failed");
            emit RecipientPaid(recipients[i].wallet, amount);
        }

        isActive = true;
        emit FundingStarted(totalRaised, toDistribute, toReserve);
    }

    function vote() external nonReentrant {
        require(isActive && !isCancelled, "Invalid state");
        require(donors[msg.sender].amount > 0, "Not a donor");
        require(!donors[msg.sender].hasVoted, "Already voted");

        uint256 weight = (donors[msg.sender].amount * 10000) / totalRaised;
        totalVotingWeight = totalVotingWeight + weight;
        donors[msg.sender].hasVoted = true;

        emit VoteCast(msg.sender, weight);

        if (totalVotingWeight >= VOTE_THRESHOLD) {
            _cancelFunding();
        }
    }

    function _cancelFunding() private {
        require(isActive && !isCancelled, "Invalid state for cancellation");
        
        isCancelled = true;
        isActive = false;

        // Get remaining balance for refunds
        uint256 remainingBalance = stablecoin.balanceOf(address(this));
        require(remainingBalance > 0, "No funds to refund");
        
        // Refund donors proportionally
        for (uint i = 0; i < donorList.length; i++) {
            address donor = donorList[i];
            uint256 refundAmount = (remainingBalance * donors[donor].amount) / totalRaised;
            if (refundAmount > 0) {
                require(stablecoin.transfer(donor, refundAmount), "Refund failed");
                emit RefundIssued(donor, refundAmount);
            }
        }

        emit FundsCancelled();
    }

    // Emergency function to rescue tokens accidentally sent to the contract
    function rescueToken(IERC20 token) external onlyOwner {
        require(address(token) != address(stablecoin), "Cannot rescue campaign token");
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, "Nothing to rescue");
        require(token.transfer(owner(), balance), "Rescue failed");
    }
}