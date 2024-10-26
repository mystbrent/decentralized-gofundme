// SPDX-License-Identifier: MIT
pragma solidity >=0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./sablier/DataTypes.sol";
import "./sablier/ISablierV2LockupLinear.sol";

/// @title DecentralizedGoFundMe
/// @notice A decentralized fundraising platform that enables donors to contribute stablecoins
/// which are then streamed to recipients over time with voting-based cancellation
/// @dev Uses Sablier V2 for token streaming and implements a donation voting mechanism
contract DecentralizedGoFundMe is ReentrancyGuard, Ownable {
    using SafeMath for uint256;

    /// @notice Structure to track recipient information
    /// @param wallet The recipient's address
    /// @param allocation Percentage allocation of funds (in basis points, 100% = 10000)
    /// @param streamId The Sablier stream ID for this recipient
    struct Recipient {
        address wallet;
        uint256 allocation;
        uint256 streamId;
    }

    /// @notice Structure to track donor information
    /// @param amount The total amount donated
    /// @param hasVoted Whether the donor has voted to cancel the streams
    struct Donor {
        uint256 amount;
        bool hasVoted;
    }

    // Constants
    /// @notice Platform fee percentage in basis points (1% = 100)
    uint256 private constant PLATFORM_FEE = 100;
    /// @notice Voting threshold in basis points (50% = 5000)
    uint256 private constant VOTE_THRESHOLD = 5000;
    /// @notice Duration for token streaming (30 days)
    uint40 private constant STREAM_DURATION = 30 days;

    /// @notice The ERC20 stablecoin used for donations
    IERC20 public immutable stablecoin;
    /// @notice Address that receives platform fees
    address public immutable platformWallet;
    /// @notice Sablier V2 contract for token streaming
    ISablierV2LockupLinear public immutable sablier;

    // State variables
    /// @notice Mapping of donor addresses to their donation info
    mapping(address => Donor) public donors;
    /// @notice List of all donor addresses for iteration
    address[] public donorList;
    /// @notice Array of all recipients and their allocations
    Recipient[] public recipients;
    /// @notice Total amount of stablecoins raised
    uint256 public totalRaised;
    /// @notice Total weight of votes cast to cancel streams
    uint256 public totalVotingWeight;
    /// @notice Whether funds are currently being streamed
    bool public isStreaming;
    /// @notice Whether streams have been cancelled
    bool public isCancelled;

    // Events
    /// @notice Emitted when a donation is received
    event DonationReceived(address indexed donor, uint256 amount);
    /// @notice Emitted when a stream is started for a recipient
    event StreamStarted(
        address indexed recipient,
        uint256 streamId,
        uint256 amount
    );
    /// @notice Emitted when a donor casts a vote
    event VoteCast(address indexed donor, uint256 weight);
    /// @notice Emitted when all streams are cancelled
    event StreamsCancelled();
    /// @notice Emitted when a donor receives a refund
    event RefundIssued(address indexed donor, uint256 amount);

    /// @notice Initializes the fundraising contract
    /// @param _stablecoin Address of the stablecoin contract
    /// @param _platformWallet Address to receive platform fees
    /// @param _sablier Address of Sablier V2 contract
    /// @param _recipients Array of recipient addresses
    /// @param _allocations Array of recipient allocations (in basis points)
    constructor(
        address _stablecoin,
        address _platformWallet,
        address _sablier,
        address[] memory _recipients,
        uint256[] memory _allocations
    ) {
        require(
            _recipients.length == _allocations.length,
            "Invalid recipients/allocations"
        );
        require(_recipients.length > 0, "No recipients");

        stablecoin = IERC20(_stablecoin);
        platformWallet = _platformWallet;
        sablier = ISablierV2LockupLinear(_sablier);

        uint256 totalAllocation;
        for (uint i = 0; i < _recipients.length; i++) {
            require(_recipients[i] != address(0), "Invalid recipient");
            require(_allocations[i] > 0, "Invalid allocation");
            totalAllocation = totalAllocation.add(_allocations[i]);
            recipients.push(
                Recipient({
                    wallet: _recipients[i],
                    allocation: _allocations[i],
                    streamId: 0
                })
            );
        }
        require(totalAllocation == 10000, "Total allocation must be 100%");
    }

    /// @notice Allows users to donate stablecoins to the fund
    /// @param amount The amount of stablecoins to donate
    /// @dev Requires prior approval of stablecoin transfer
    function donate(uint256 amount) external nonReentrant {
        require(!isStreaming && !isCancelled, "Fund not accepting donations");
        require(amount > 0, "Invalid amount");

        // Transfer stablecoins to contract
        stablecoin.transferFrom(msg.sender, address(this), amount);

        // Record donation
        if (donors[msg.sender].amount == 0) {
            donorList.push(msg.sender);
        }
        donors[msg.sender].amount = donors[msg.sender].amount.add(amount);
        totalRaised = totalRaised.add(amount);

        emit DonationReceived(msg.sender, amount);
    }

    /// @notice Starts streaming tokens to recipients
    /// @dev Only callable by owner, initiates Sablier streams for all recipients
    function startStreaming() external onlyOwner nonReentrant {
        require(!isStreaming && !isCancelled, "Invalid state");
        require(totalRaised > 0, "No funds raised");

        // Calculate platform fee
        uint256 platformFeeAmount = totalRaised.mul(PLATFORM_FEE).div(10000);
        uint256 remainingAmount = totalRaised.sub(platformFeeAmount);

        // Transfer platform fee
        stablecoin.transfer(platformWallet, platformFeeAmount);

        // Start streams for each recipient
        for (uint i = 0; i < recipients.length; i++) {
            uint256 recipientAmount = remainingAmount
                .mul(recipients[i].allocation)
                .div(10000);

            // Approve Sablier to spend tokens
            stablecoin.approve(address(sablier), recipientAmount);

            // Create Sablier stream using the correct library namespace
            LockupLinear.CreateWithDurations memory params = LockupLinear
                .CreateWithDurations({
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

    /// @notice Allows donors to vote for cancelling streams
    /// @dev Vote weight is proportional to donation amount
    function vote() external nonReentrant {
        require(isStreaming && !isCancelled, "Invalid state");
        require(donors[msg.sender].amount > 0, "Not a donor");
        require(!donors[msg.sender].hasVoted, "Already voted");

        uint256 weight = donors[msg.sender].amount.mul(10000).div(totalRaised);
        totalVotingWeight = totalVotingWeight.add(weight);
        donors[msg.sender].hasVoted = true;

        emit VoteCast(msg.sender, weight);

        if (totalVotingWeight >= VOTE_THRESHOLD) {
            _cancelStreams();
        }
    }

    /// @notice Internal function to cancel all streams and refund donors
    /// @dev Called when voting threshold is reached
    function _cancelStreams() private {
        require(isStreaming && !isCancelled, "Invalid state");

        // Cancel all Sablier streams and collect refunds
        uint256 totalRefunded = 0;
        for (uint i = 0; i < recipients.length; i++) {
            if (recipients[i].streamId > 0) {
                // Get stream details before cancelling to calculate refund amount
                LockupLinear.StreamLL memory stream = sablier.getStream(
                    recipients[i].streamId
                );
                uint256 depositedAmount = uint256(stream.amounts.deposited);
                uint256 withdrawnAmount = uint256(stream.amounts.withdrawn);

                // Calculate refundable amount (total - withdrawn)
                uint256 refundableAmount = depositedAmount - withdrawnAmount;

                // Cancel the stream
                sablier.cancel(recipients[i].streamId);

                // Add refundable amount to total
                totalRefunded = totalRefunded.add(refundableAmount);
            }
        }

        // Mark as cancelled
        isCancelled = true;
        isStreaming = false;

        emit StreamsCancelled();

        // Refund donors proportionally
        for (uint i = 0; i < donorList.length; i++) {
            address donor = donorList[i];
            if (donors[donor].amount > 0) {
                uint256 refundAmount = totalRefunded
                    .mul(donors[donor].amount)
                    .div(totalRaised);
                if (refundAmount > 0) {
                    require(
                        stablecoin.transfer(donor, refundAmount),
                        "Refund failed"
                    );
                    emit RefundIssued(donor, refundAmount);
                }
            }
        }
    }

    /// @notice Allows owner to rescue accidentally sent tokens
    /// @param token The ERC20 token to rescue
    /// @dev Cannot rescue the stablecoin used for donations
    function rescueToken(IERC20 token) external onlyOwner {
        require(
            address(token) != address(stablecoin),
            "Cannot rescue stream token"
        );
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, "Nothing to rescue");
        token.transfer(owner(), balance);
    }
}
