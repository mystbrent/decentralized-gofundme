// SPDX-License-Identifier: MIT
pragma solidity >=0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./sablier/DataTypes.sol";
import "./sablier/ISablierV2LockupLinear.sol";

contract DecentralizedGoFundMe is ReentrancyGuard, Ownable {
    using SafeMath for uint256;

    struct Recipient {
        address wallet;
        uint256 allocation;
        uint256 streamId;
    }

    struct Donor {
        uint256 amount;
        bool hasVoted;
    }

    uint256 private constant PLATFORM_FEE = 100;
    uint256 private constant VOTE_THRESHOLD = 5000;
    uint40 private constant STREAM_DURATION = 30 days;

    IERC20 public immutable stablecoin;
    address public immutable platformWallet;
    ISablierV2LockupLinear public immutable sablier;

    mapping(address => Donor) public donors;
    address[] public donorList;
    Recipient[] public recipients;
    uint256 public totalRaised;
    uint256 public totalVotingWeight;
    bool public isStreaming;
    bool public isCancelled;

    event DonationReceived(address indexed donor, uint256 amount);
    event StreamStarted(address indexed recipient, uint256 streamId, uint256 amount);
    event VoteCast(address indexed donor, uint256 weight);
    event StreamsCancelled();
    event RefundIssued(address indexed donor, uint256 amount);

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

    function getVotingWeight(address donor) public view returns (uint256) {
        if (totalRaised == 0) return 0;
        return donors[donor].amount.mul(10000).div(totalRaised);
    }

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

    function _cancelStreams() private {
        require(isStreaming && !isCancelled, "Invalid state");

        uint256 totalRefunded = 0;
        for (uint i = 0; i < recipients.length; i++) {
            if (recipients[i].streamId > 0) {
                LockupLinear.StreamLL memory stream = sablier.getStream(recipients[i].streamId);
                uint256 depositedAmount = uint256(stream.amounts.deposited);
                uint256 withdrawnAmount = uint256(stream.amounts.withdrawn);
                uint256 refundableAmount = depositedAmount - withdrawnAmount;

                sablier.cancel(recipients[i].streamId);
                totalRefunded = totalRefunded.add(refundableAmount);
            }
        }

        isCancelled = true;
        isStreaming = false;

        emit StreamsCancelled();

        for (uint i = 0; i < donorList.length; i++) {
            address donor = donorList[i];
            if (donors[donor].amount > 0) {
                uint256 refundAmount = totalRefunded.mul(donors[donor].amount).div(totalRaised);
                if (refundAmount > 0) {
                    require(stablecoin.transfer(donor, refundAmount), "Refund failed");
                    emit RefundIssued(donor, refundAmount);
                }
            }
        }
    }

    function rescueToken(IERC20 token) external onlyOwner {
        require(address(token) != address(stablecoin), "Cannot rescue stream token");
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, "Nothing to rescue");
        token.transfer(owner(), balance);
    }
}