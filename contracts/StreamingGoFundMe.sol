// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./sablier/DataTypes.sol";
import "./sablier/ISablierV2LockupLinear.sol";
import "./UniversityRegistry.sol";

/**
 * @title StreamingGoFundMe
 * @notice A decentralized fundraising platform for universities that accepts stablecoin donations
 * and streams funds using the Sablier protocol
 * @dev Implements donation collection, fund streaming, voting mechanism, and refund functionality
 * with validation against a UniversityRegistry
 */
contract StreamingGoFundMe is ReentrancyGuard, Ownable {
    using SafeMath for uint256;

    /**
     * @notice Information about a university fund recipient
     * @param wallet The university's wallet address
     * @param allocation Percentage allocation in basis points (e.g., 5000 = 50%)
     * @param streamId The Sablier stream ID for this recipient, 0 if not streaming
     */
    struct Recipient {
        address wallet;
        uint256 allocation;
        uint256 streamId;
    }

    /**
     * @notice Information about a donor's contribution and voting status
     * @param amount Total amount donated in stablecoin units
     * @param hasVoted Whether the donor has voted to cancel streams
     */
    struct Donor {
        uint256 amount;
        bool hasVoted;
    }

    /// @notice Platform fee taken from total donations (100 = 1% in basis points)
    uint256 private constant PLATFORM_FEE = 100;
    
    /// @notice Voting threshold for stream cancellation (5000 = 50% in basis points)
    uint256 private constant VOTE_THRESHOLD = 5000;
    
    /// @notice Duration for which funds will be streamed to recipients
    uint40 private constant STREAM_DURATION = 30 days;

    /// @notice The stablecoin used for donations and streaming
    IERC20 public immutable stablecoin;
    
    /// @notice Address that receives platform fees
    address public immutable platformWallet;
    
    /// @notice Sablier protocol contract for stream management
    ISablierV2LockupLinear public immutable sablier;
    
    /// @notice Registry contract for validating university recipients
    UniversityRegistry public immutable universityRegistry;

    /// @notice Maps donor addresses to their donation and voting information
    mapping(address => Donor) public donors;
    
    /// @notice List of all donor addresses for refund distribution
    address[] public donorList;
    
    /// @notice Array of recipient universities and their allocation details
    Recipient[] public recipients;
    
    /// @notice Total amount of stablecoins donated
    uint256 public totalRaised;
    
    /// @notice Total voting weight of donors who voted to cancel
    uint256 public totalVotingWeight;
    
    /// @notice Whether funds are currently being streamed
    bool public isStreaming;
    
    /// @notice Whether the fund has been cancelled
    bool public isCancelled;

    /// @notice Emitted when a donation is received
    event DonationReceived(address indexed donor, uint256 amount);
    
    /// @notice Emitted when a stream is started for a recipient
    event StreamStarted(address indexed recipient, uint256 streamId, uint256 amount);
    
    /// @notice Emitted when a donor casts a vote to cancel
    event VoteCast(address indexed donor, uint256 weight);
    
    /// @notice Emitted when all streams are cancelled
    event StreamsCancelled();
    
    /// @notice Emitted when a refund is issued to a donor
    event RefundIssued(address indexed donor, uint256 amount);

    /**
     * @notice Initializes the fundraising contract with university recipients
     * @param _stablecoin Address of the stablecoin contract
     * @param _platformWallet Address to receive platform fees
     * @param _registry Address of the university registry contract
     * @param _sablier Address of Sablier V2 contract
     * @param _universitySymbols Array of university symbols from the registry
     * @param _allocations Array of allocation percentages in basis points
     */
    constructor(
        address _stablecoin,
        address _platformWallet,
        address _registry,
        address _sablier,
        string[] memory _universitySymbols,
        uint256[] memory _allocations
    ) Ownable(msg.sender) {
        require(_universitySymbols.length == _allocations.length, "Invalid symbols/allocations");
        require(_universitySymbols.length > 0, "No recipients");

        stablecoin = IERC20(_stablecoin);
        platformWallet = _platformWallet;
        sablier = ISablierV2LockupLinear(_sablier);
        universityRegistry = UniversityRegistry(_registry);

        uint256 totalAllocation;
        for (uint i = 0; i < _universitySymbols.length; i++) {
            (,address wallet,bool isActive) = universityRegistry.getUniversity(_universitySymbols[i]);
            require(wallet != address(0), "Invalid university");
            require(isActive, "University not active");
            require(_allocations[i] > 0, "Invalid allocation");
            
            totalAllocation = totalAllocation.add(_allocations[i]);
            recipients.push(Recipient({
                wallet: wallet,
                allocation: _allocations[i],
                streamId: 0
            }));
        }
        require(totalAllocation == 10000, "Total allocation must be 100%");
    }

    /**
     * @notice Allows users to donate stablecoins to the fund
     * @param amount Amount of stablecoins to donate
     * @dev Requires approval for stablecoin transfer
     */
    function donate(uint256 amount) external nonReentrant {
        require(!isStreaming && !isCancelled, "Fund not accepting donations");
        require(amount > 0, "Invalid amount");

        stablecoin.transferFrom(msg.sender, address(this), amount);

        if (donors[msg.sender].amount == 0) {
            donorList.push(msg.sender);
        }
        donors[msg.sender].amount = donors[msg.sender].amount.add(amount);
        totalRaised = totalRaised.add(amount);

        emit DonationReceived(msg.sender, amount);
    }

    /**
     * @notice Starts streaming funds to university recipients
     * @dev Only callable by contract owner. Creates Sablier streams for each recipient.
     */
    function startStreaming() external onlyOwner nonReentrant {
        require(!isStreaming && !isCancelled, "Invalid state");
        require(totalRaised > 0, "No funds raised");

        // Verify recipients are still valid
        for (uint i = 0; i < recipients.length; i++) {
            require(
                universityRegistry.isValidUniversityWallet(recipients[i].wallet),
                "University no longer valid"
            );
        }

        uint256 platformFeeAmount = totalRaised.mul(PLATFORM_FEE).div(10000);
        uint256 remainingAmount = totalRaised.sub(platformFeeAmount);

        stablecoin.transfer(platformWallet, platformFeeAmount);

        for (uint i = 0; i < recipients.length; i++) {
            uint256 recipientAmount = remainingAmount.mul(recipients[i].allocation).div(10000);
            stablecoin.approve(address(sablier), recipientAmount);

            LockupLinear.CreateWithDurations memory params = LockupLinear.CreateWithDurations({
                sender: address(this),
                recipient: recipients[i].wallet,
                totalAmount: uint128(recipientAmount),
                asset: stablecoin,
                cancelable: true,
                transferable: false,
                durations: LockupLinear.Durations({
                    cliff: 0,
                    total: STREAM_DURATION
                }),
                broker: Broker({account: address(0), fee: UD60x18.wrap(0)})
            });

            uint256 streamId = sablier.createWithDurations(params);
            recipients[i].streamId = streamId;
            emit StreamStarted(recipients[i].wallet, streamId, recipientAmount);
        }

        isStreaming = true;
    }

    /**
     * @notice Calculates a donor's voting weight
     * @param donor Address of the donor
     * @return Voting weight in basis points (e.g., 1000 = 10%)
     */
    function getVotingWeight(address donor) public view returns (uint256) {
        if (totalRaised == 0) return 0;
        return donors[donor].amount.mul(10000).div(totalRaised);
    }

    /**
     * @notice Allows donors to vote for cancelling streams
     * @dev Automatically triggers cancellation if threshold is reached
     */
    function vote() external nonReentrant {
        require(isStreaming && !isCancelled, "Invalid state");
        require(donors[msg.sender].amount > 0, "Not a donor");
        require(!donors[msg.sender].hasVoted, "Already voted");

        uint256 weight = getVotingWeight(msg.sender);
        totalVotingWeight = totalVotingWeight.add(weight);
        donors[msg.sender].hasVoted = true;

        emit VoteCast(msg.sender, weight);

        if (totalVotingWeight >= VOTE_THRESHOLD) {
            _cancelStreams();
        }
    }

    /**
     * @notice Internal function to cancel streams and process refunds
     * @dev Called automatically when voting threshold is reached
     */
    function _cancelStreams() private {
        isCancelled = true;
        isStreaming = false;

        uint256 initialBalance = stablecoin.balanceOf(address(this));
        
        // Cancel all active streams
        for (uint i = 0; i < recipients.length; i++) {
            if (recipients[i].streamId > 0) {
                try sablier.cancel(recipients[i].streamId) {} catch {}
            }
        }

        emit StreamsCancelled();

        // Process refunds
        uint256 finalBalance = stablecoin.balanceOf(address(this));
        uint256 refundableAmount = finalBalance.sub(initialBalance);

        if (refundableAmount > 0) {
            for (uint i = 0; i < donorList.length; i++) {
                address donor = donorList[i];
                if (donors[donor].amount > 0) {
                    uint256 refundAmount = refundableAmount.mul(donors[donor].amount).div(totalRaised);
                    if (refundAmount > 0) {
                        stablecoin.transfer(donor, refundAmount);
                        emit RefundIssued(donor, refundAmount);
                    }
                }
            }
        }
    }
}