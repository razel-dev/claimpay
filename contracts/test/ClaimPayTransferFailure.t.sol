// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";
import {ClaimPay} from "../src/ClaimPay.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";

contract TemporarilyUnavailableUSDC is MockUSDC {
    error TransfersUnavailable();

    bool private _transfersUnavailable;

    function setTransfersUnavailable(bool unavailable) external {
        _transfersUnavailable = unavailable;
    }

    function transfer(address to, uint256 value) public override returns (bool) {
        if (_transfersUnavailable) {
            revert TransfersUnavailable();
        }
        return super.transfer(to, value);
    }
}

contract ClaimPayTransferFailureTest is Test {
    uint256 internal constant AMOUNT = 100e6;

    ClaimPay internal claimPay;
    TemporarilyUnavailableUSDC internal token;

    address internal client = makeAddr("client");
    address internal provider = makeAddr("provider");
    address internal arbiter = makeAddr("arbiter");

    function setUp() public {
        token = new TemporarilyUnavailableUSDC();
        claimPay = new ClaimPay(address(token));
        token.mint(client, AMOUNT);
        vm.prank(client);
        token.approve(address(claimPay), AMOUNT);
    }

    function testDirectPaymentPreservesStateWhenTransferFails() public {
        uint256 agreementId = _createSubmittedAgreement(address(0));
        token.setTransfersUnavailable(true);

        vm.prank(client);
        vm.expectRevert(TemporarilyUnavailableUSDC.TransfersUnavailable.selector);
        claimPay.approveMilestone(agreementId, 0);

        _assertStillEscrowed(agreementId, ClaimPay.MilestoneStatus.Submitted);
    }

    function testArbiterSettlementPreservesStateWhenTransferFails() public {
        uint256 agreementId = _createSubmittedAgreement(arbiter);
        vm.prank(client);
        claimPay.disputeMilestone(agreementId, 0);
        token.setTransfersUnavailable(true);

        vm.prank(arbiter);
        vm.expectRevert(TemporarilyUnavailableUSDC.TransfersUnavailable.selector);
        claimPay.resolveDispute(agreementId, 0, ClaimPay.DisputeResolution.PayProvider);

        _assertStillEscrowed(agreementId, ClaimPay.MilestoneStatus.Disputed);
    }

    function testMutualRefundPreservesProposalOnFailureAndCanBeRetried() public {
        uint256 agreementId = _createSubmittedAgreement(address(0));
        vm.startPrank(client);
        claimPay.disputeMilestone(agreementId, 0);
        claimPay.proposeSettlement(agreementId, 0, ClaimPay.DisputeResolution.RefundClient);
        vm.stopPrank();
        token.setTransfersUnavailable(true);

        vm.prank(provider);
        vm.expectRevert(TemporarilyUnavailableUSDC.TransfersUnavailable.selector);
        claimPay.acceptSettlement(agreementId, 0, ClaimPay.DisputeResolution.RefundClient);

        _assertStillEscrowed(agreementId, ClaimPay.MilestoneStatus.Disputed);
        (bool exists, address proposer, ClaimPay.DisputeResolution resolution) =
            claimPay.getSettlementProposal(agreementId, 0);
        assertTrue(exists);
        assertEq(proposer, client);
        assertEq(uint256(resolution), uint256(ClaimPay.DisputeResolution.RefundClient));

        token.setTransfersUnavailable(false);
        vm.prank(provider);
        claimPay.acceptSettlement(agreementId, 0, ClaimPay.DisputeResolution.RefundClient);

        _assertStatuses(agreementId, ClaimPay.AgreementStatus.Completed, ClaimPay.MilestoneStatus.Refunded);
        (bool existsAfterRetry,,) = claimPay.getSettlementProposal(agreementId, 0);
        assertFalse(existsAfterRetry);
        assertEq(token.balanceOf(address(claimPay)), 0);
        assertEq(token.balanceOf(client), AMOUNT);
        assertEq(token.balanceOf(provider), 0);
    }

    function _createSubmittedAgreement(address resolver) internal returns (uint256 agreementId) {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Delivery";
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = AMOUNT;

        vm.prank(client);
        agreementId = claimPay.createAgreement(provider, resolver, descriptions, amounts);
        vm.prank(provider);
        claimPay.submitMilestone(agreementId, 0);
    }

    function _assertStillEscrowed(uint256 agreementId, ClaimPay.MilestoneStatus milestoneStatus) internal view {
        _assertStatuses(agreementId, ClaimPay.AgreementStatus.Active, milestoneStatus);
        assertEq(token.balanceOf(address(claimPay)), AMOUNT);
        assertEq(token.balanceOf(client), 0);
        assertEq(token.balanceOf(provider), 0);
    }

    function _assertStatuses(
        uint256 agreementId,
        ClaimPay.AgreementStatus expectedAgreementStatus,
        ClaimPay.MilestoneStatus expectedMilestoneStatus
    ) internal view {
        (,,, ClaimPay.AgreementStatus agreementStatus,) = claimPay.getAgreement(agreementId);
        (,, ClaimPay.MilestoneStatus milestoneStatus) = claimPay.getMilestone(agreementId, 0);
        assertEq(uint256(agreementStatus), uint256(expectedAgreementStatus));
        assertEq(uint256(milestoneStatus), uint256(expectedMilestoneStatus));
    }
}
