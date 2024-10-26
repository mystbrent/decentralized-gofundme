// SPDX-License-Identifier: MIT
pragma solidity >=0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./sablier/DataTypes.sol";
import "./sablier/ISablierV2LockupLinear.sol";

/**
 * @title StreamingGoFundMe
 * @notice A decentralized fundraising platform that accepts stablecoin donations and 
 * streams funds to recipients using Sablier protocol
 * @dev Implements donation collection, fund streaming, voting mechanism, and refund functionality
 */
contract StreamingGoFundMe is ReentrancyGuard, Ownable {
    using SafeMath for uint256;

    /**
     * @notice Stores information about a fund recipient
     * @param wallet The recipient's address
     * @param allocation Percentage allocation (in basis points, e.g., 5000 = 50%)
     * @param streamId Sablier stream ID for this recipient
     */
    struct Recipient {
        address wallet;
        uint256 allocation;
        uint256 streamId;
    }

    /**
     * @notice Stores information about a donor
     * @param amount Total amount donated
     * @param hasVoted Whether the donor has voted to cancel streams
     */
    struct Donor {
        uint256 amount;
        bool hasVoted;
    }

    // Constants
    uint256 private constant PLATFORM_FEE = 100; // 1% fee in basis points
    uint256 private constant VOTE_THRESHOLD = 5000; // 50% voting threshold in basis points
    uint40 private constant STREAM_DURATION = 30 days;

    // Core contract references
    IERC20 public immutable stablecoin;
    address public immutable platformWallet;
    ISablierV2LockupLinear public immutable sablier;

    // State variables
    mapping(address => Donor) public donors;
    address[] public donorList;
    Recipient[] public recipients;
    uint256 public totalRaised;
    uint256 public totalVotingWeight;
    bool public isStreaming;
    bool public isCancelled;

    // Events for core functionality
    event DonationReceived(address indexed donor, uint256 amount);
    event StreamStarted(address indexed recipient, uint256 streamId, uint256 amount);
    event VoteCast(address indexed donor, uint256 weight);
    event StreamsCancelled();
    event RefundIssued(address indexed donor, uint256 amount);

    // Additional events for debugging
    event StreamCancellationInitiated(uint256 totalVotingWeight);
    event StreamCancellationAttempt(uint256 indexed streamId, bool success);
    event VestedAmountCalculated(uint256 indexed streamId, uint256 vestedAmount);
    event RefundCalculation(
        uint256 initialBalance,
        uint256 finalBalance,
        uint256 totalVested,
        uint256 refundableAmount
    );
    event DonorRefundCalculated(
        address indexed donor, 
        uint256 donationAmount, 
        uint256 refundAmount
    );

    /**
     * @notice Contract constructor
     * @param _stablecoin Address of the stablecoin contract
     * @param _platformWallet Address to receive platform fees
     * @param _sablier Address of Sablier V2 contract
     * @param _recipients Array of recipient addresses
     * @param _allocations Array of recipient allocations (in basis points)
     */
    constructor(
        address _stablecoin,
        address _platformWallet,
        address _sablier,
        address[] memory _recipients,
        uint256[] memory _allocations
    ) Ownable(msg.sender) {
        require(_recipients.length == _allocations.length, "Invalid recipients/allocations");
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

    /**
     * @notice Calculates a donor's voting weight in basis points
     * @param donor Address of the donor
     * @return uint256 Voting weight in basis points (e.g., 1000 = 10%)
     */
    function getVotingWeight(address donor) public view returns (uint256) {
        if (totalRaised == 0) return 0;
        return donors[donor].amount.mul(10000).div(totalRaised);
    }

    /**
     * @notice Allows users to donate stablecoins to the fund
     * @param amount Amount of stablecoins to donate
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
     * @notice Initiates streaming of funds to recipients
     * @dev Only callable by contract owner
     */
    function startStreaming() external onlyOwner nonReentrant {
        require(!isStreaming && !isCancelled, "Invalid state");
        require(totalRaised > 0, "No funds raised");

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
            emit StreamCancellationInitiated(totalVotingWeight);
            _cancelStreams();
        }
    }

    /**
     * @notice Internal function to handle stream cancellation and refunds
     * @dev Cancels all active streams and distributes refunds proportionally
     */
    function _cancelStreams() private {
        require(isStreaming && !isCancelled, "Invalid state");

        isCancelled = true;
        isStreaming = false;

        uint256 initialBalance = stablecoin.balanceOf(address(this));
        uint256 totalVested = 0;
        
        // Calculate total vested amount
        for (uint i = 0; i < recipients.length; i++) {
            if (recipients[i].streamId > 0) {
                try sablier.getStream(recipients[i].streamId) returns (LockupLinear.StreamLL memory stream) {
                    uint256 vestedAmount = uint256(stream.amounts.withdrawn);
                    totalVested = totalVested.add(vestedAmount);
                    emit VestedAmountCalculated(recipients[i].streamId, vestedAmount);
                } catch {
                    emit StreamCancellationAttempt(recipients[i].streamId, false);
                    continue;
                }
            }
        }

        // Cancel streams
        for (uint i = 0; i < recipients.length; i++) {
            if (recipients[i].streamId > 0) {
                try sablier.cancel(recipients[i].streamId) {
                    emit StreamCancellationAttempt(recipients[i].streamId, true);
                } catch {
                    emit StreamCancellationAttempt(recipients[i].streamId, false);
                    continue;
                }
            }
        }

        emit StreamsCancelled();

        uint256 finalBalance = stablecoin.balanceOf(address(this));
        uint256 refundableAmount = finalBalance.sub(initialBalance);

        emit RefundCalculation(
            initialBalance,
            finalBalance,
            totalVested,
            refundableAmount
        );

        if (refundableAmount > 0) {
            for (uint i = 0; i < donorList.length; i++) {
                address donor = donorList[i];
                if (donors[donor].amount > 0) {
                    uint256 refundAmount = refundableAmount.mul(donors[donor].amount).div(totalRaised);
                    
                    emit DonorRefundCalculated(
                        donor,
                        donors[donor].amount,
                        refundAmount
                    );

                    if (refundAmount > 0) {
                        require(stablecoin.transfer(donor, refundAmount), "Refund failed");
                        emit RefundIssued(donor, refundAmount);
                    }
                }
            }
        }
    }

    /**
     * @notice Allows owner to rescue accidentally sent tokens
     * @param token Address of the token to rescue
     * @dev Cannot be used to rescue the stablecoin used for streaming
     */
    function rescueToken(IERC20 token) external onlyOwner {
        require(address(token) != address(stablecoin), "Cannot rescue stream token");
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, "Nothing to rescue");
        token.transfer(owner(), balance);
    }
}