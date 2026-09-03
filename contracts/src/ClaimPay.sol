// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

contract ClaimPay {
    error InvalidProvider();
    error InvalidArbiter();
    error EmptyMilestones();
    error MilestoneDataMismatch();
    error EmptyMilestoneDescription(uint256 index);
    error InvalidMilestoneAmount(uint256 index);

    enum AgreementStatus {
        Active,
        Completed
    }

    enum MilestoneStatus {
        Pending,
        Submitted,
        Disputed,
        Paid,
        Rejected
    }

    struct Milestone {
        string description;
        uint256 amount;
        MilestoneStatus status;
    }

    struct Agreement {
        address client;
        address provider;
        address arbiter;
        AgreementStatus status;
        Milestone[] milestones;
    }

    uint256 public agreementCount;
    mapping(uint256 => Agreement) private _agreements;

    function createAgreement(
        address provider,
        address arbiter,
        string[] calldata descriptions,
        uint256[] calldata amounts
    ) external returns (uint256 agreementId) {
        if (provider == address(0) || provider == msg.sender) {
            revert InvalidProvider();
        }
        if (arbiter != address(0) && (arbiter == msg.sender || arbiter == provider)) {
            revert InvalidArbiter();
        }
        if (descriptions.length == 0) {
            revert EmptyMilestones();
        }
        if (descriptions.length != amounts.length) {
            revert MilestoneDataMismatch();
        }
        for (uint256 i; i < descriptions.length; ++i) {
            if (bytes(descriptions[i]).length == 0) {
                revert EmptyMilestoneDescription(i);
            }
            if (amounts[i] == 0) {
                revert InvalidMilestoneAmount(i);
            }
        }
    }
}
