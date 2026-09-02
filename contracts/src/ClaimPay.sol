// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

contract ClaimPay {
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
}
