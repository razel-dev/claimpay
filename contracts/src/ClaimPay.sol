// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract ClaimPay {
    using SafeERC20 for IERC20;
    error InvalidProvider();
    error InvalidArbiter();
    error EmptyMilestones();
    error MilestoneDataMismatch();
    error EmptyMilestoneDescription(uint256 index);
    error InvalidMilestoneAmount(uint256 index);
    error AgreementNotFound(uint256 agreementId);
    error MilestoneNotFound(uint256 agreementId, uint256 milestoneIndex);
    error InvalidPaymentToken();
    error NotAgreementProvider(uint256 agreementId, address caller);
    error InvalidMilestoneStatus(
        uint256 agreementId,
        uint256 milestoneIndex,
        MilestoneStatus currentStatus
    );
    error NotAgreementClient(uint256 agreementId, address caller);
    error NoDisputeResolverConfigured(uint256 agreementId);
    error NotAgreementResolver(uint256 agreementId, address caller);
    error DisputeResolverAlreadyConfigured(uint256 agreementId);
    error NotAgreementParty(uint256 agreementId, address caller);
    error SettlementProposalNotFound(
        uint256 agreementId,
        uint256 milestoneIndex
    );
    error SettlementProposerCannotAccept(
        uint256 agreementId,
        uint256 milestoneIndex
    );
    error SettlementProposalMismatch(
        uint256 agreementId,
        uint256 milestoneIndex,
        DisputeResolution expectedResolution,
        DisputeResolution proposedResolution
    );

    event AgreementCreated(
        uint256 indexed agreementId,
        address indexed client,
        address indexed provider,
        address arbiter,
        uint256 milestoneCount
    );

    event MilestoneSubmitted(
        uint256 indexed agreementId,
        uint256 indexed milestoneIndex,
        address indexed provider
    );

    event MilestonePaid(
        uint256 indexed agreementId,
        uint256 indexed milestoneIndex,
        address indexed provider,
        uint256 amount
    );

    event AgreementCompleted(uint256 indexed agreementId);

    event MilestoneDisputed(
        uint256 indexed agreementId,
        uint256 indexed milestoneIndex,
        address indexed client
    );

    event MilestoneRefunded(
        uint256 indexed agreementId,
        uint256 indexed milestoneIndex,
        address indexed client,
        uint256 amount
    );

    event DisputeResolved(
        uint256 indexed agreementId,
        uint256 indexed milestoneIndex,
        address indexed resolver,
        DisputeResolution resolution
    );

    event SettlementProposed(
        uint256 indexed agreementId,
        uint256 indexed milestoneIndex,
        address indexed proposer,
        DisputeResolution resolution
    );

    event SettlementAccepted(
        uint256 indexed agreementId,
        uint256 indexed milestoneIndex,
        address indexed acceptor,
        DisputeResolution resolution
    );

    enum AgreementStatus {
        Active,
        Completed
    }

    enum MilestoneStatus {
        Pending,
        Submitted,
        Disputed,
        Paid,
        Refunded
    }

    struct Milestone {
        string description;
        uint256 amount;
        MilestoneStatus status;
    }

    enum DisputeResolution {
        PayProvider,
        RefundClient
    }

    struct SettlementProposal {
        address proposer;
        DisputeResolution resolution;
    }

    struct Agreement {
        address client;
        address provider;
        address arbiter;
        AgreementStatus status;
        Milestone[] milestones;
    }

    IERC20 public immutable paymentToken;

    uint256 public agreementCount;
    mapping(uint256 => Agreement) private _agreements;
    mapping(uint256 => mapping(uint256 => SettlementProposal))
        private _settlementProposals;

    constructor(address paymentTokenAddress) {
        if (paymentTokenAddress == address(0)) {
            revert InvalidPaymentToken();
        }

        paymentToken = IERC20(paymentTokenAddress);
    }

    function createAgreement(
        address provider,
        address arbiter,
        string[] calldata descriptions,
        uint256[] calldata amounts
    ) external returns (uint256 agreementId) {
        if (provider == address(0) || provider == msg.sender) {
            revert InvalidProvider();
        }
        if (
            arbiter != address(0) &&
            (arbiter == msg.sender || arbiter == provider)
        ) {
            revert InvalidArbiter();
        }
        if (descriptions.length == 0) {
            revert EmptyMilestones();
        }
        if (descriptions.length != amounts.length) {
            revert MilestoneDataMismatch();
        }

        uint256 totalAmount;

        for (uint256 i; i < descriptions.length; ++i) {
            if (bytes(descriptions[i]).length == 0) {
                revert EmptyMilestoneDescription(i);
            }
            if (amounts[i] == 0) {
                revert InvalidMilestoneAmount(i);
            }

            totalAmount += amounts[i];
        }

        paymentToken.safeTransferFrom(msg.sender, address(this), totalAmount);

        agreementCount++;
        agreementId = agreementCount;

        Agreement storage agreement = _agreements[agreementId];

        agreement.client = msg.sender;
        agreement.provider = provider;
        agreement.arbiter = arbiter;
        agreement.status = AgreementStatus.Active;

        for (uint256 i; i < descriptions.length; ++i) {
            agreement.milestones.push(
                Milestone({
                    description: descriptions[i],
                    amount: amounts[i],
                    status: MilestoneStatus.Pending
                })
            );
        }

        emit AgreementCreated(
            agreementId,
            msg.sender,
            provider,
            arbiter,
            descriptions.length
        );
    }

    function submitMilestone(
        uint256 agreementId,
        uint256 milestoneIndex
    ) external {
        Agreement storage agreement = _agreements[agreementId];
        if (agreement.client == address(0)) {
            revert AgreementNotFound(agreementId);
        }
        if (msg.sender != agreement.provider) {
            revert NotAgreementProvider(agreementId, msg.sender);
        }
        if (milestoneIndex >= agreement.milestones.length) {
            revert MilestoneNotFound(agreementId, milestoneIndex);
        }

        Milestone storage milestone = agreement.milestones[milestoneIndex];
        if (milestone.status != MilestoneStatus.Pending) {
            revert InvalidMilestoneStatus(
                agreementId,
                milestoneIndex,
                milestone.status
            );
        }

        milestone.status = MilestoneStatus.Submitted;

        emit MilestoneSubmitted(agreementId, milestoneIndex, msg.sender);
    }

    function disputeMilestone(
        uint256 agreementId,
        uint256 milestoneIndex
    ) external {
        Agreement storage agreement = _agreements[agreementId];

        if (agreement.client == address(0)) {
            revert AgreementNotFound(agreementId);
        }

        if (msg.sender != agreement.client) {
            revert NotAgreementClient(agreementId, msg.sender);
        }

        if (milestoneIndex >= agreement.milestones.length) {
            revert MilestoneNotFound(agreementId, milestoneIndex);
        }

        Milestone storage milestone = agreement.milestones[milestoneIndex];

        if (milestone.status != MilestoneStatus.Submitted) {
            revert InvalidMilestoneStatus(
                agreementId,
                milestoneIndex,
                milestone.status
            );
        }

        milestone.status = MilestoneStatus.Disputed;

        emit MilestoneDisputed(agreementId, milestoneIndex, msg.sender);
    }

    function resolveDispute(
        uint256 agreementId,
        uint256 milestoneIndex,
        DisputeResolution resolution
    ) external {
        Agreement storage agreement = _agreements[agreementId];

        if (agreement.client == address(0)) {
            revert AgreementNotFound(agreementId);
        }

        if (agreement.arbiter == address(0)) {
            revert NoDisputeResolverConfigured(agreementId);
        }

        if (msg.sender != agreement.arbiter) {
            revert NotAgreementResolver(agreementId, msg.sender);
        }

        if (milestoneIndex >= agreement.milestones.length) {
            revert MilestoneNotFound(agreementId, milestoneIndex);
        }

        Milestone storage milestone = agreement.milestones[milestoneIndex];

        if (milestone.status != MilestoneStatus.Disputed) {
            revert InvalidMilestoneStatus(
                agreementId,
                milestoneIndex,
                milestone.status
            );
        }

        bool allMilestonesSettled = _settleMilestone(
            agreementId,
            milestoneIndex,
            agreement,
            milestone,
            resolution
        );

        emit DisputeResolved(
            agreementId,
            milestoneIndex,
            msg.sender,
            resolution
        );

        if (allMilestonesSettled) {
            emit AgreementCompleted(agreementId);
        }
    }

    function proposeSettlement(
        uint256 agreementId,
        uint256 milestoneIndex,
        DisputeResolution resolution
    ) external {
        Agreement storage agreement = _agreements[agreementId];

        if (agreement.client == address(0)) {
            revert AgreementNotFound(agreementId);
        }

        if (
            msg.sender != agreement.client && msg.sender != agreement.provider
        ) {
            revert NotAgreementParty(agreementId, msg.sender);
        }

        if (agreement.arbiter != address(0)) {
            revert DisputeResolverAlreadyConfigured(agreementId);
        }

        if (milestoneIndex >= agreement.milestones.length) {
            revert MilestoneNotFound(agreementId, milestoneIndex);
        }

        Milestone storage milestone = agreement.milestones[milestoneIndex];

        if (milestone.status != MilestoneStatus.Disputed) {
            revert InvalidMilestoneStatus(
                agreementId,
                milestoneIndex,
                milestone.status
            );
        }

        SettlementProposal storage proposal = _settlementProposals[agreementId][
            milestoneIndex
        ];

        proposal.proposer = msg.sender;
        proposal.resolution = resolution;

        emit SettlementProposed(
            agreementId,
            milestoneIndex,
            msg.sender,
            resolution
        );
    }

    function acceptSettlement(
        uint256 agreementId,
        uint256 milestoneIndex,
        DisputeResolution expectedResolution
    ) external {
        Agreement storage agreement = _agreements[agreementId];

        if (agreement.client == address(0)) {
            revert AgreementNotFound(agreementId);
        }

        if (
            msg.sender != agreement.client && msg.sender != agreement.provider
        ) {
            revert NotAgreementParty(agreementId, msg.sender);
        }

        if (agreement.arbiter != address(0)) {
            revert DisputeResolverAlreadyConfigured(agreementId);
        }

        if (milestoneIndex >= agreement.milestones.length) {
            revert MilestoneNotFound(agreementId, milestoneIndex);
        }

        Milestone storage milestone = agreement.milestones[milestoneIndex];

        if (milestone.status != MilestoneStatus.Disputed) {
            revert InvalidMilestoneStatus(
                agreementId,
                milestoneIndex,
                milestone.status
            );
        }

        SettlementProposal storage proposal = _settlementProposals[agreementId][
            milestoneIndex
        ];

        if (proposal.proposer == address(0)) {
            revert SettlementProposalNotFound(agreementId, milestoneIndex);
        }

        if (msg.sender == proposal.proposer) {
            revert SettlementProposerCannotAccept(agreementId, milestoneIndex);
        }

        if (expectedResolution != proposal.resolution) {
            revert SettlementProposalMismatch(
                agreementId,
                milestoneIndex,
                expectedResolution,
                proposal.resolution
            );
        }

        DisputeResolution acceptedResolution = proposal.resolution;

        delete _settlementProposals[agreementId][milestoneIndex];

        bool allMilestonesSettled = _settleMilestone(
            agreementId,
            milestoneIndex,
            agreement,
            milestone,
            acceptedResolution
        );

        emit SettlementAccepted(
            agreementId,
            milestoneIndex,
            msg.sender,
            acceptedResolution
        );

        if (allMilestonesSettled) {
            emit AgreementCompleted(agreementId);
        }
    }

    function approveMilestone(
        uint256 agreementId,
        uint256 milestoneIndex
    ) external {
        Agreement storage agreement = _agreements[agreementId];

        if (agreement.client == address(0)) {
            revert AgreementNotFound(agreementId);
        }

        if (msg.sender != agreement.client) {
            revert NotAgreementClient(agreementId, msg.sender);
        }

        if (milestoneIndex >= agreement.milestones.length) {
            revert MilestoneNotFound(agreementId, milestoneIndex);
        }

        Milestone storage milestone = agreement.milestones[milestoneIndex];

        if (milestone.status != MilestoneStatus.Submitted) {
            revert InvalidMilestoneStatus(
                agreementId,
                milestoneIndex,
                milestone.status
            );
        }

        milestone.status = MilestoneStatus.Paid;

        bool allMilestonesSettled = _allMilestonesSettled(agreement);

        if (allMilestonesSettled) {
            agreement.status = AgreementStatus.Completed;
        }

        paymentToken.safeTransfer(agreement.provider, milestone.amount);

        emit MilestonePaid(
            agreementId,
            milestoneIndex,
            agreement.provider,
            milestone.amount
        );

        if (allMilestonesSettled) {
            emit AgreementCompleted(agreementId);
        }
    }

    function getAgreement(
        uint256 agreementId
    )
        external
        view
        returns (
            address client,
            address provider,
            address arbiter,
            AgreementStatus status,
            uint256 milestoneCount
        )
    {
        if (agreementId == 0 || agreementId > agreementCount) {
            revert AgreementNotFound(agreementId);
        }
        Agreement storage agreement = _agreements[agreementId];
        return (
            agreement.client,
            agreement.provider,
            agreement.arbiter,
            agreement.status,
            agreement.milestones.length
        );
    }

    function _settleMilestone(
        uint256 agreementId,
        uint256 milestoneIndex,
        Agreement storage agreement,
        Milestone storage milestone,
        DisputeResolution resolution
    ) private returns (bool allMilestonesSettled) {
        address recipient;

        if (resolution == DisputeResolution.PayProvider) {
            milestone.status = MilestoneStatus.Paid;
            recipient = agreement.provider;
        } else {
            milestone.status = MilestoneStatus.Refunded;
            recipient = agreement.client;
        }

        allMilestonesSettled = _allMilestonesSettled(agreement);

        if (allMilestonesSettled) {
            agreement.status = AgreementStatus.Completed;
        }

        paymentToken.safeTransfer(recipient, milestone.amount);

        if (resolution == DisputeResolution.PayProvider) {
            emit MilestonePaid(
                agreementId,
                milestoneIndex,
                agreement.provider,
                milestone.amount
            );
        } else {
            emit MilestoneRefunded(
                agreementId,
                milestoneIndex,
                agreement.client,
                milestone.amount
            );
        }

        return allMilestonesSettled;
    }

    function _allMilestonesSettled(
        Agreement storage agreement
    ) private view returns (bool) {
        for (uint256 i; i < agreement.milestones.length; ++i) {
            MilestoneStatus status = agreement.milestones[i].status;

            if (
                status != MilestoneStatus.Paid &&
                status != MilestoneStatus.Refunded
            ) {
                return false;
            }
        }

        return true;
    }

    function getMilestone(
        uint256 agreementId,
        uint256 milestoneIndex
    )
        external
        view
        returns (
            string memory description,
            uint256 amount,
            MilestoneStatus status
        )
    {
        if (agreementId == 0 || agreementId > agreementCount) {
            revert AgreementNotFound(agreementId);
        }
        Agreement storage agreement = _agreements[agreementId];
        if (milestoneIndex >= agreement.milestones.length) {
            revert MilestoneNotFound(agreementId, milestoneIndex);
        }
        Milestone storage milestone = agreement.milestones[milestoneIndex];
        return (milestone.description, milestone.amount, milestone.status);
    }

    function getSettlementProposal(
    uint256 agreementId,
    uint256 milestoneIndex
)
    external
    view
    returns (
        bool exists,
        address proposer,
        DisputeResolution resolution
    )
{
    if (agreementId == 0 || agreementId > agreementCount) {
        revert AgreementNotFound(agreementId);
    }

    Agreement storage agreement = _agreements[agreementId];

    if (milestoneIndex >= agreement.milestones.length) {
        revert MilestoneNotFound(agreementId, milestoneIndex);
    }

    SettlementProposal storage proposal =
        _settlementProposals[agreementId][milestoneIndex];

    return (
        proposal.proposer != address(0),
        proposal.proposer,
        proposal.resolution
    );
}
}
