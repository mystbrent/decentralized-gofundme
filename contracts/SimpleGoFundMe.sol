// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./UniversityRegistry.sol";

/**
 * @title SimpleGoFundMe
 * @notice A decentralized fundraising platform for universities with a two-phase distribution model
 * @dev Uses a registry to validate university recipients and implements a voting mechanism for fund cancellation
 */
contract SimpleGoFundMe is ReentrancyGuard, Ownable {
    /**
     * @notice Structure defining a funding recipient (university)
     * @param wallet The wallet address of the university (validated through registry)
     * @param allocation Percentage allocation in basis points (1 = 0.01%)
     */
    struct Recipient {
        address wallet;
        uint256 allocation;
    }

    /**
     * @notice Structure tracking donor information
     * @param amount Total amount donated by this donor
     * @param hasVoted Whether this donor has voted for cancellation
     */
    struct Donor {
        uint256 amount;
        bool hasVoted;
    }

    // Constants for fee and distribution calculations (in basis points, 1 = 0.01%)
    uint256 private constant PLATFORM_FEE = 100; // 1% platform fee
    uint256 private constant VOTE_THRESHOLD = 5000; // 50% required for cancellation
    uint256 private constant INITIAL_DISTRIBUTION = 7000; // 70% distributed initially
    uint256 private constant RESERVE_AMOUNT = 3000; // 30% kept as reserve

    // Core contract references
    UniversityRegistry public immutable universityRegistry; // Registry of validated universities
    IERC20 public immutable stablecoin; // Stablecoin used for donations
    address public immutable platformWallet; // Wallet receiving platform fees

    // Donation and recipient tracking
    mapping(address => Donor) public donors; // Tracks all donors and their information
    address[] public donorList; // List of all donor addresses for iteration
    Recipient[] public recipients; // List of recipient universities and their allocations
    uint256 public totalRaised; // Total amount of donations received
    uint256 public totalVotingWeight; // Cumulative weight of votes for cancellation
    bool public isActive; // Whether fundraising is currently active
    bool public isCancelled; // Whether fundraising has been cancelled

    // Events for state changes and important operations
    event DonationReceived(address indexed donor, uint256 amount);
    event FundingStarted(
        uint256 totalAmount,
        uint256 distributed,
        uint256 reserved
    );
    event RecipientPaid(address indexed recipient, uint256 amount);
    event VoteCast(address indexed donor, uint256 weight);
    event FundsCancelled();
    event RefundIssued(address indexed donor, uint256 amount);

    /**
     * @notice Initializes a new fundraising campaign
     * @dev Validates universities through registry and verifies allocations
     * @param _stablecoin Address of the stablecoin contract used for donations
     * @param _platformWallet Address receiving platform fees
     * @param _registry Address of the UniversityRegistry contract
     * @param _universitySymbols Array of university symbols from registry
     * @param _allocations Array of allocation percentages (in basis points)
     */
    constructor(
        address _stablecoin,
        address _platformWallet,
        address _registry,
        string[] memory _universitySymbols,
        uint256[] memory _allocations
    ) Ownable(msg.sender) {
        require(
            _universitySymbols.length == _allocations.length,
            "Invalid recipients/allocations"
        );
        require(_universitySymbols.length > 0, "No recipients");

        stablecoin = IERC20(_stablecoin);
        platformWallet = _platformWallet;
        universityRegistry = UniversityRegistry(_registry);

        uint256 totalAllocation;
        for (uint i = 0; i < _universitySymbols.length; i++) {
            // Validate university through registry
            (, address wallet, bool isActive) = universityRegistry
                .getUniversity(_universitySymbols[i]);
            require(wallet != address(0), "Invalid university");
            require(isActive, "University not active");
            require(_allocations[i] > 0, "Invalid allocation");

            totalAllocation = totalAllocation + _allocations[i];
            recipients.push(
                Recipient({wallet: wallet, allocation: _allocations[i]})
            );
        }
        require(totalAllocation == 10000, "Total allocation must be 100%");
    }

    /**
     * @notice Allows donors to contribute stablecoins to the fundraising
     * @dev Requires prior approval of stablecoin transfer
     * @param amount Amount of stablecoins to donate
     */
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

    /**
     * @notice Starts the fundraising distribution process
     * @dev Distributes initial 70% to recipients and reserves 30%
     */
    function startFunding() external onlyOwner nonReentrant {
        require(!isActive && !isCancelled, "Invalid state");
        require(totalRaised > 0, "No funds raised");

        uint256 platformFeeAmount = (totalRaised * PLATFORM_FEE) / 10000;
        uint256 remainingAfterFee = totalRaised - platformFeeAmount;

        // Calculate distribution amounts
        uint256 toDistribute = (remainingAfterFee * INITIAL_DISTRIBUTION) /
            10000;
        uint256 toReserve = remainingAfterFee - toDistribute;

        // Transfer platform fee
        require(
            stablecoin.transfer(platformWallet, platformFeeAmount),
            "Platform fee transfer failed"
        );

        // Distribute to universities
        for (uint i = 0; i < recipients.length; i++) {
            uint256 amount = (toDistribute * recipients[i].allocation) / 10000;
            require(
                stablecoin.transfer(recipients[i].wallet, amount),
                "Recipient transfer failed"
            );
            emit RecipientPaid(recipients[i].wallet, amount);
        }

        isActive = true;
        emit FundingStarted(totalRaised, toDistribute, toReserve);
    }

    /**
     * @notice Allows donors to vote for cancelling the fundraising
     * @dev Voting weight is proportional to donation amount
     */
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

    /**
     * @notice Internal function to handle fundraising cancellation
     * @dev Distributes remaining funds proportionally to donors
     */
    function _cancelFunding() private {
        require(isActive && !isCancelled, "Invalid state for cancellation");

        isCancelled = true;
        isActive = false;

        uint256 remainingBalance = stablecoin.balanceOf(address(this));
        require(remainingBalance > 0, "No funds to refund");

        // Process refunds proportionally
        for (uint i = 0; i < donorList.length; i++) {
            address donor = donorList[i];
            uint256 refundAmount = (remainingBalance * donors[donor].amount) /
                totalRaised;
            if (refundAmount > 0) {
                require(
                    stablecoin.transfer(donor, refundAmount),
                    "Refund failed"
                );
                emit RefundIssued(donor, refundAmount);
            }
        }

        emit FundsCancelled();
    }

    /**
     * @notice Emergency function to recover non-campaign tokens
     * @dev Cannot be used to withdraw campaign stablecoins
     * @param token Address of token to recover
     */
    function rescueToken(IERC20 token) external onlyOwner {
        require(
            address(token) != address(stablecoin),
            "Cannot rescue campaign token"
        );
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, "Nothing to rescue");
        require(token.transfer(owner(), balance), "Rescue failed");
    }
}
