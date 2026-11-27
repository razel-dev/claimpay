// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";
import {ClaimPay} from "../src/ClaimPay.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";

contract ClaimPayIsolationTest is Test {
    uint256 internal constant MILESTONE_INDEX = 0;
    uint256 internal constant MAX_AMOUNT = 10_000 * 10 ** 6;

    ClaimPay internal claimPay;
    MockUSDC internal mockUSDC;

    address internal client = makeAddr("client");
    address internal firstProvider = makeAddr("firstProvider");
    address internal secondProvider = makeAddr("secondProvider");

    event AgreementCompleted(uint256 indexed agreementId);

    function setUp() public {
        mockUSDC = new MockUSDC();
        claimPay = new ClaimPay(address(mockUSDC));
    }

    function testFuzzSettlementIsolatedAcrossAgreements(uint256 firstAmount, uint256 secondAmount) public {
        firstAmount = bound(firstAmount, 1, MAX_AMOUNT);
        secondAmount = bound(secondAmount, 1, MAX_AMOUNT);
        mockUSDC.mint(client, firstAmount + secondAmount);
        vm.prank(client);
        mockUSDC.approve(address(claimPay), firstAmount + secondAmount);

        uint256 firstId = _createDisputedAgreement(firstProvider, firstAmount);
        uint256 secondId = _createDisputedAgreement(secondProvider, secondAmount);
        assertNotEq(firstId, secondId);
        assertEq(mockUSDC.balanceOf(address(claimPay)), firstAmount + secondAmount);

        vm.prank(firstProvider);
        claimPay.proposeSettlement(firstId, MILESTONE_INDEX, ClaimPay.DisputeResolution.PayProvider);
        _assertNoProposal(secondId);

        vm.prank(client);
        claimPay.proposeSettlement(secondId, MILESTONE_INDEX, ClaimPay.DisputeResolution.RefundClient);
        _assertProposal(firstId, firstProvider, ClaimPay.DisputeResolution.PayProvider);
        _assertProposal(secondId, client, ClaimPay.DisputeResolution.RefundClient);

        vm.expectEmit(true, false, false, false, address(claimPay));
        emit AgreementCompleted(firstId);
        vm.prank(client);
        claimPay.acceptSettlement(firstId, MILESTONE_INDEX, ClaimPay.DisputeResolution.PayProvider);

        _assertState(firstId, firstAmount, ClaimPay.AgreementStatus.Completed, ClaimPay.MilestoneStatus.Paid);
        _assertNoProposal(firstId);
        _assertState(secondId, secondAmount, ClaimPay.AgreementStatus.Active, ClaimPay.MilestoneStatus.Disputed);
        _assertProposal(secondId, client, ClaimPay.DisputeResolution.RefundClient);
        assertEq(mockUSDC.balanceOf(address(claimPay)), secondAmount);
        assertEq(mockUSDC.balanceOf(client), 0);
        assertEq(mockUSDC.balanceOf(firstProvider), firstAmount);
        assertEq(mockUSDC.balanceOf(secondProvider), 0);

        vm.expectEmit(true, false, false, false, address(claimPay));
        emit AgreementCompleted(secondId);
        vm.prank(secondProvider);
        claimPay.acceptSettlement(secondId, MILESTONE_INDEX, ClaimPay.DisputeResolution.RefundClient);

        _assertState(secondId, secondAmount, ClaimPay.AgreementStatus.Completed, ClaimPay.MilestoneStatus.Refunded);
        _assertNoProposal(secondId);
        _assertState(firstId, firstAmount, ClaimPay.AgreementStatus.Completed, ClaimPay.MilestoneStatus.Paid);
        _assertNoProposal(firstId);
        assertEq(mockUSDC.balanceOf(address(claimPay)), 0);
        assertEq(mockUSDC.balanceOf(client), secondAmount);
        assertEq(mockUSDC.balanceOf(firstProvider), firstAmount);
        assertEq(mockUSDC.balanceOf(secondProvider), 0);
    }

    function _createDisputedAgreement(address provider, uint256 amount) internal returns (uint256 agreementId) {
        string[] memory descriptions = new string[](1);
        descriptions[MILESTONE_INDEX] = "Delivery";
        uint256[] memory amounts = new uint256[](1);
        amounts[MILESTONE_INDEX] = amount;

        vm.prank(client);
        agreementId = claimPay.createAgreement(provider, address(0), descriptions, amounts);
        vm.prank(provider);
        claimPay.submitMilestone(agreementId, MILESTONE_INDEX);
        vm.prank(client);
        claimPay.disputeMilestone(agreementId, MILESTONE_INDEX);
    }

    function _assertState(
        uint256 agreementId,
        uint256 expectedAmount,
        ClaimPay.AgreementStatus expectedAgreementStatus,
        ClaimPay.MilestoneStatus expectedMilestoneStatus
    ) internal view {
        (,,, ClaimPay.AgreementStatus agreementStatus,) = claimPay.getAgreement(agreementId);
        (, uint256 amount, ClaimPay.MilestoneStatus milestoneStatus) =
            claimPay.getMilestone(agreementId, MILESTONE_INDEX);
        assertEq(amount, expectedAmount);
        assertEq(uint256(agreementStatus), uint256(expectedAgreementStatus));
        assertEq(uint256(milestoneStatus), uint256(expectedMilestoneStatus));
    }

    function _assertProposal(
        uint256 agreementId,
        address expectedProposer,
        ClaimPay.DisputeResolution expectedResolution
    ) internal view {
        (bool exists, address proposer, ClaimPay.DisputeResolution resolution) =
            claimPay.getSettlementProposal(agreementId, MILESTONE_INDEX);
        assertTrue(exists);
        assertEq(proposer, expectedProposer);
        assertEq(uint256(resolution), uint256(expectedResolution));
    }

    function _assertNoProposal(uint256 agreementId) internal view {
        (bool exists, address proposer,) = claimPay.getSettlementProposal(agreementId, MILESTONE_INDEX);
        assertFalse(exists);
        assertEq(proposer, address(0));
    }
}
