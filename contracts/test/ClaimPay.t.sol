// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";
import {ClaimPay} from "../src/ClaimPay.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {
    IERC20Errors
} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract ClaimPayTest is Test {
    ClaimPay internal claimPay;
    MockUSDC internal mockUSDC;

    uint256 internal constant CLIENT_BALANCE = 10_000 * 10 ** 6;

    address internal client = makeAddr("client");
    address internal provider = makeAddr("provider");
    address internal arbiter = makeAddr("arbiter");
    address internal unfundedClient = makeAddr("unfundedClient");

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
        ClaimPay.DisputeResolution resolution
    );

    event SettlementProposed(
        uint256 indexed agreementId,
        uint256 indexed milestoneIndex,
        address indexed proposer,
        ClaimPay.DisputeResolution resolution
    );

    event SettlementAccepted(
        uint256 indexed agreementId,
        uint256 indexed milestoneIndex,
        address indexed acceptor,
        ClaimPay.DisputeResolution resolution
    );

    function setUp() public {
        mockUSDC = new MockUSDC();
        claimPay = new ClaimPay(address(mockUSDC));

        mockUSDC.mint(client, CLIENT_BALANCE);

        vm.prank(client);
        mockUSDC.approve(address(claimPay), CLIENT_BALANCE);
    }

    function testInitialAgreementCountIsZero() public view {
        assertEq(claimPay.agreementCount(), 0);
    }

    function testCreateAgreement() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Maquette";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500;

        vm.prank(client);

        uint256 agreementId = claimPay.createAgreement(
            provider,
            arbiter,
            descriptions,
            amounts
        );

        assertEq(agreementId, 1);
        assertEq(claimPay.agreementCount(), 1);

        (
            address storedClient,
            address storedProvider,
            address storedArbiter,
            ClaimPay.AgreementStatus storedStatus,
            uint256 milestoneCount
        ) = claimPay.getAgreement(agreementId);

        assertEq(storedClient, client);
        assertEq(storedProvider, provider);
        assertEq(storedArbiter, arbiter);
        assertEq(
            uint256(storedStatus),
            uint256(ClaimPay.AgreementStatus.Active)
        );
        assertEq(milestoneCount, 1);

        (
            string memory storedDescription,
            uint256 storedAmount,
            ClaimPay.MilestoneStatus storedMilestoneStatus
        ) = claimPay.getMilestone(agreementId, 0);

        assertEq(storedDescription, "Maquette");
        assertEq(storedAmount, 500);
        assertEq(
            uint256(storedMilestoneStatus),
            uint256(ClaimPay.MilestoneStatus.Pending)
        );
        assertEq(mockUSDC.balanceOf(client), CLIENT_BALANCE - amounts[0]);
        assertEq(mockUSDC.balanceOf(address(claimPay)), amounts[0]);
    }

    function testEmitAgreementCreated() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Maquette";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500;
        vm.expectEmit(true, true, true, true, address(claimPay));

        emit AgreementCreated(1, client, provider, arbiter, 1);
        vm.prank(client);

        claimPay.createAgreement(provider, arbiter, descriptions, amounts);
    }

    function testCreateAgreementWithoutArbiter() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Maquette";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500;

        vm.prank(client);

        uint256 agreementId = claimPay.createAgreement(
            provider,
            address(0),
            descriptions,
            amounts
        );

        assertEq(agreementId, 1);
        assertEq(claimPay.agreementCount(), 1);
    }

    function testRevertWhenProviderIsZero() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Maquette";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500;

        vm.expectRevert(ClaimPay.InvalidProvider.selector);
        vm.prank(client);

        claimPay.createAgreement(address(0), arbiter, descriptions, amounts);
    }

    function testRevertWhenProviderIsClient() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Maquette";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500;

        vm.expectRevert(ClaimPay.InvalidProvider.selector);
        vm.prank(client);

        claimPay.createAgreement(client, arbiter, descriptions, amounts);
    }

    function testRevertWhenArbiterIsClient() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Maquette";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500;

        vm.expectRevert(ClaimPay.InvalidArbiter.selector);
        vm.prank(client);

        claimPay.createAgreement(provider, client, descriptions, amounts);
    }

    function testRevertWhenArbiterIsProvider() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Maquette";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500;

        vm.expectRevert(ClaimPay.InvalidArbiter.selector);
        vm.prank(client);

        claimPay.createAgreement(provider, provider, descriptions, amounts);
    }

    function testRevertWhenNoMilestones() public {
        string[] memory descriptions = new string[](0);
        uint256[] memory amounts = new uint256[](0);

        vm.expectRevert(ClaimPay.EmptyMilestones.selector);
        vm.prank(client);

        claimPay.createAgreement(provider, arbiter, descriptions, amounts);
    }

    function testRevertWhenMilestoneDataLengthsMismatch() public {
        string[] memory descriptions = new string[](2);
        descriptions[0] = "Maquette";
        descriptions[1] = "Developpement";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500;

        vm.expectRevert(ClaimPay.MilestoneDataMismatch.selector);
        vm.prank(client);

        claimPay.createAgreement(provider, arbiter, descriptions, amounts);
    }

    function testRevertWhenMilestoneDescriptionIsEmpty() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500;

        vm.expectRevert(
            abi.encodeWithSelector(
                ClaimPay.EmptyMilestoneDescription.selector,
                0
            )
        );
        vm.prank(client);

        claimPay.createAgreement(provider, arbiter, descriptions, amounts);
    }

    function testRevertWhenMilestoneAmountIsZero() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Maquette";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 0;

        vm.expectRevert(
            abi.encodeWithSelector(ClaimPay.InvalidMilestoneAmount.selector, 0)
        );
        vm.prank(client);

        claimPay.createAgreement(provider, arbiter, descriptions, amounts);
    }

    function testRevertWhenAgreementDoesNotExist() public {
        vm.expectRevert(
            abi.encodeWithSelector(ClaimPay.AgreementNotFound.selector, 1)
        );

        claimPay.getAgreement(1);
    }

    function testRevertWhenGettingMilestoneFromUnknownAgreement() public {
        vm.expectRevert(
            abi.encodeWithSelector(ClaimPay.AgreementNotFound.selector, 1)
        );

        claimPay.getMilestone(1, 0);
    }

    function testRevertWhenMilestoneDoesNotExist() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Maquette";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            arbiter,
            descriptions,
            amounts
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ClaimPay.MilestoneNotFound.selector,
                agreementId,
                1
            )
        );

        claimPay.getMilestone(agreementId, 1);
    }

    function testPaymentTokenIsConfigured() public view {
        assertEq(address(claimPay.paymentToken()), address(mockUSDC));
    }

    function testRevertWhenPaymentTokenIsZero() public {
        vm.expectRevert(ClaimPay.InvalidPaymentToken.selector);

        new ClaimPay(address(0));
    }

    function testCreateAgreementTransfersTotalMilestoneAmount() public {
        string[] memory descriptions = new string[](2);
        descriptions[0] = "Maquette";
        descriptions[1] = "Developpement";

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 500;
        amounts[1] = 700;

        uint256 expectedTotal = amounts[0] + amounts[1];

        vm.prank(client);
        claimPay.createAgreement(provider, arbiter, descriptions, amounts);

        assertEq(mockUSDC.balanceOf(address(claimPay)), expectedTotal);
        assertEq(mockUSDC.balanceOf(client), CLIENT_BALANCE - expectedTotal);
    }

    function testRevertWhenAllowanceIsInsufficient() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Maquette";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500;

        vm.prank(client);
        mockUSDC.approve(address(claimPay), 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(claimPay),
                0,
                amounts[0]
            )
        );
        vm.prank(client);
        claimPay.createAgreement(provider, arbiter, descriptions, amounts);

        assertEq(claimPay.agreementCount(), 0);
    }

    function testRevertWhenBalanceIsInsufficient() public {
        assertEq(mockUSDC.balanceOf(unfundedClient), 0);
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Maquette";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500 * 10 ** 6;
        vm.prank(unfundedClient);
        mockUSDC.approve(address(claimPay), amounts[0]);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                unfundedClient,
                0,
                amounts[0]
            )
        );
        vm.prank(unfundedClient);
        claimPay.createAgreement(provider, arbiter, descriptions, amounts);

        assertEq(claimPay.agreementCount(), 0);
    }

    function testProviderCanSubmitMilestone() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Maquette";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            arbiter,
            descriptions,
            amounts
        );
        vm.prank(provider);
        claimPay.submitMilestone(agreementId, 0);

        (, , ClaimPay.MilestoneStatus storedStatus) = claimPay.getMilestone(
            agreementId,
            0
        );

        assertEq(
            uint256(storedStatus),
            uint256(ClaimPay.MilestoneStatus.Submitted)
        );
    }

    function testRevertWhenNonProviderSubmitsMilestone() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Maquette";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            arbiter,
            descriptions,
            amounts
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ClaimPay.NotAgreementProvider.selector,
                agreementId,
                client
            )
        );
        vm.prank(client);
        claimPay.submitMilestone(agreementId, 0);
        (, , ClaimPay.MilestoneStatus storedStatus) = claimPay.getMilestone(
            agreementId,
            0
        );

        assertEq(
            uint256(storedStatus),
            uint256(ClaimPay.MilestoneStatus.Pending)
        );
    }

    function testRevertWhenSubmittingMilestoneDoesNotExist() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Maquette";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            arbiter,
            descriptions,
            amounts
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ClaimPay.MilestoneNotFound.selector,
                agreementId,
                1
            )
        );
        vm.prank(provider);
        claimPay.submitMilestone(agreementId, 1);
        (, , ClaimPay.MilestoneStatus storedStatus) = claimPay.getMilestone(
            agreementId,
            0
        );

        assertEq(
            uint256(storedStatus),
            uint256(ClaimPay.MilestoneStatus.Pending)
        );
    }

    function testRevertWhenSubmittingMilestoneTwice() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Maquette";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            arbiter,
            descriptions,
            amounts
        );

        vm.prank(provider);
        claimPay.submitMilestone(agreementId, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                ClaimPay.InvalidMilestoneStatus.selector,
                agreementId,
                0,
                ClaimPay.MilestoneStatus.Submitted
            )
        );
        vm.prank(provider);
        claimPay.submitMilestone(agreementId, 0);
        (, , ClaimPay.MilestoneStatus storedStatus) = claimPay.getMilestone(
            agreementId,
            0
        );
        assertEq(
            uint256(storedStatus),
            uint256(ClaimPay.MilestoneStatus.Submitted)
        );
    }
    function testRevertWhenSubmittingMilestoneFromUnknownAgreement() public {
        vm.expectRevert(
            abi.encodeWithSelector(ClaimPay.AgreementNotFound.selector, 1)
        );
        vm.prank(provider);
        claimPay.submitMilestone(1, 0);
        assertEq(claimPay.agreementCount(), 0);
    }

    function testEmitMilestoneSubmitted() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Maquette";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            arbiter,
            descriptions,
            amounts
        );

        vm.expectEmit(true, true, true, true, address(claimPay));
        emit MilestoneSubmitted(agreementId, 0, provider);

        vm.prank(provider);
        claimPay.submitMilestone(agreementId, 0);
    }

    function testClientCanApproveSubmittedMilestone() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Maquette";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            arbiter,
            descriptions,
            amounts
        );

        vm.prank(provider);
        claimPay.submitMilestone(agreementId, 0);

        uint256 providerBalanceBefore = mockUSDC.balanceOf(provider);
        uint256 claimPayBalanceBefore = mockUSDC.balanceOf(address(claimPay));

        vm.prank(client);
        claimPay.approveMilestone(agreementId, 0);

        (, , ClaimPay.MilestoneStatus storedMilestoneStatus) = claimPay
            .getMilestone(agreementId, 0);

        (
            ,
            ,
            ,
            ClaimPay.AgreementStatus storedAgreementStatus,
            uint256 milestoneCount
        ) = claimPay.getAgreement(agreementId);

        assertEq(
            uint256(storedMilestoneStatus),
            uint256(ClaimPay.MilestoneStatus.Paid)
        );

        assertEq(
            uint256(storedAgreementStatus),
            uint256(ClaimPay.AgreementStatus.Completed)
        );

        assertEq(milestoneCount, 1);

        assertEq(
            mockUSDC.balanceOf(provider),
            providerBalanceBefore + amounts[0]
        );

        assertEq(
            mockUSDC.balanceOf(address(claimPay)),
            claimPayBalanceBefore - amounts[0]
        );
    }

    function testAgreementCompletesOnlyAfterAllMilestonesArePaid() public {
        string[] memory descriptions = new string[](2);
        descriptions[0] = "Maquette";
        descriptions[1] = "Developpement";

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 500 * 10 ** 6;
        amounts[1] = 700 * 10 ** 6;

        uint256 totalAmount = amounts[0] + amounts[1];

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            arbiter,
            descriptions,
            amounts
        );

        vm.prank(provider);
        claimPay.submitMilestone(agreementId, 0);

        vm.prank(provider);
        claimPay.submitMilestone(agreementId, 1);

        uint256 providerBalanceBefore = mockUSDC.balanceOf(provider);
        uint256 claimPayBalanceBefore = mockUSDC.balanceOf(address(claimPay));

        vm.prank(client);
        claimPay.approveMilestone(agreementId, 0);

        (, , ClaimPay.MilestoneStatus firstMilestoneStatus) = claimPay
            .getMilestone(agreementId, 0);

        (
            ,
            ,
            ,
            ClaimPay.AgreementStatus statusAfterFirstPayment,
            uint256 milestoneCount
        ) = claimPay.getAgreement(agreementId);

        assertEq(
            uint256(firstMilestoneStatus),
            uint256(ClaimPay.MilestoneStatus.Paid)
        );

        assertEq(
            uint256(statusAfterFirstPayment),
            uint256(ClaimPay.AgreementStatus.Active)
        );

        assertEq(milestoneCount, 2);

        assertEq(
            mockUSDC.balanceOf(provider),
            providerBalanceBefore + amounts[0]
        );

        assertEq(
            mockUSDC.balanceOf(address(claimPay)),
            claimPayBalanceBefore - amounts[0]
        );

        vm.prank(client);
        claimPay.approveMilestone(agreementId, 1);

        (, , ClaimPay.MilestoneStatus secondMilestoneStatus) = claimPay
            .getMilestone(agreementId, 1);

        (, , , ClaimPay.AgreementStatus finalAgreementStatus, ) = claimPay
            .getAgreement(agreementId);

        assertEq(
            uint256(secondMilestoneStatus),
            uint256(ClaimPay.MilestoneStatus.Paid)
        );

        assertEq(
            uint256(finalAgreementStatus),
            uint256(ClaimPay.AgreementStatus.Completed)
        );

        assertEq(
            mockUSDC.balanceOf(provider),
            providerBalanceBefore + totalAmount
        );

        assertEq(
            mockUSDC.balanceOf(address(claimPay)),
            claimPayBalanceBefore - totalAmount
        );
    }

    function testRevertWhenApprovingPendingMilestone() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Maquette";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            arbiter,
            descriptions,
            amounts
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ClaimPay.InvalidMilestoneStatus.selector,
                agreementId,
                0,
                ClaimPay.MilestoneStatus.Pending
            )
        );

        vm.prank(client);
        claimPay.approveMilestone(agreementId, 0);
    }

    function testRevertWhenNonClientApprovesMilestone() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Maquette";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            arbiter,
            descriptions,
            amounts
        );

        vm.prank(provider);
        claimPay.submitMilestone(agreementId, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                ClaimPay.NotAgreementClient.selector,
                agreementId,
                provider
            )
        );

        vm.prank(provider);
        claimPay.approveMilestone(agreementId, 0);
    }

    function testRevertWhenApprovingMilestoneFromUnknownAgreement() public {
        vm.expectRevert(
            abi.encodeWithSelector(ClaimPay.AgreementNotFound.selector, 1)
        );

        vm.prank(client);
        claimPay.approveMilestone(1, 0);

        assertEq(claimPay.agreementCount(), 0);
    }

    function testRevertWhenApprovingMilestoneDoesNotExist() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Maquette";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            arbiter,
            descriptions,
            amounts
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ClaimPay.MilestoneNotFound.selector,
                agreementId,
                1
            )
        );

        vm.prank(client);
        claimPay.approveMilestone(agreementId, 1);
    }

    function testRevertWhenApprovingMilestoneTwice() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Maquette";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            arbiter,
            descriptions,
            amounts
        );

        vm.prank(provider);
        claimPay.submitMilestone(agreementId, 0);

        vm.prank(client);
        claimPay.approveMilestone(agreementId, 0);

        uint256 providerBalanceAfterFirstPayment = mockUSDC.balanceOf(provider);
        uint256 claimPayBalanceAfterFirstPayment = mockUSDC.balanceOf(
            address(claimPay)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ClaimPay.InvalidMilestoneStatus.selector,
                agreementId,
                0,
                ClaimPay.MilestoneStatus.Paid
            )
        );

        vm.prank(client);
        claimPay.approveMilestone(agreementId, 0);

        assertEq(
            mockUSDC.balanceOf(provider),
            providerBalanceAfterFirstPayment
        );

        assertEq(
            mockUSDC.balanceOf(address(claimPay)),
            claimPayBalanceAfterFirstPayment
        );

        (, , ClaimPay.MilestoneStatus storedStatus) = claimPay.getMilestone(
            agreementId,
            0
        );

        assertEq(uint256(storedStatus), uint256(ClaimPay.MilestoneStatus.Paid));
    }

    function testEmitMilestonePaidAndAgreementCompleted() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Maquette";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            arbiter,
            descriptions,
            amounts
        );

        vm.prank(provider);
        claimPay.submitMilestone(agreementId, 0);

        vm.expectEmit(true, true, true, true, address(claimPay));
        emit MilestonePaid(agreementId, 0, provider, amounts[0]);

        vm.expectEmit(true, false, false, false, address(claimPay));
        emit AgreementCompleted(agreementId);

        vm.prank(client);
        claimPay.approveMilestone(agreementId, 0);
    }
    function testClientCanDisputeSubmittedMilestone() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Maquette";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            arbiter,
            descriptions,
            amounts
        );

        vm.prank(provider);
        claimPay.submitMilestone(agreementId, 0);

        uint256 providerBalanceBefore = mockUSDC.balanceOf(provider);
        uint256 claimPayBalanceBefore = mockUSDC.balanceOf(address(claimPay));

        vm.prank(client);
        claimPay.disputeMilestone(agreementId, 0);

        (, , ClaimPay.MilestoneStatus milestoneStatus) = claimPay.getMilestone(
            agreementId,
            0
        );

        (, , , ClaimPay.AgreementStatus agreementStatus, ) = claimPay
            .getAgreement(agreementId);

        assertEq(
            uint256(milestoneStatus),
            uint256(ClaimPay.MilestoneStatus.Disputed)
        );

        assertEq(
            uint256(agreementStatus),
            uint256(ClaimPay.AgreementStatus.Active)
        );

        assertEq(mockUSDC.balanceOf(provider), providerBalanceBefore);
        assertEq(mockUSDC.balanceOf(address(claimPay)), claimPayBalanceBefore);
    }

    function testClientCanDisputeSubmittedMilestoneWithoutArbiter() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Maquette";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            address(0),
            descriptions,
            amounts
        );

        vm.prank(provider);
        claimPay.submitMilestone(agreementId, 0);

        uint256 providerBalanceBefore = mockUSDC.balanceOf(provider);
        uint256 claimPayBalanceBefore = mockUSDC.balanceOf(address(claimPay));

        vm.prank(client);
        claimPay.disputeMilestone(agreementId, 0);

        (, , ClaimPay.MilestoneStatus milestoneStatus) = claimPay.getMilestone(
            agreementId,
            0
        );

        (, , address storedArbiter, , ) = claimPay.getAgreement(agreementId);

        assertEq(storedArbiter, address(0));

        assertEq(
            uint256(milestoneStatus),
            uint256(ClaimPay.MilestoneStatus.Disputed)
        );

        assertEq(mockUSDC.balanceOf(provider), providerBalanceBefore);

        assertEq(mockUSDC.balanceOf(address(claimPay)), claimPayBalanceBefore);
    }

    function testRevertWhenNonClientDisputesMilestone() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Maquette";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            arbiter,
            descriptions,
            amounts
        );

        vm.prank(provider);
        claimPay.submitMilestone(agreementId, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                ClaimPay.NotAgreementClient.selector,
                agreementId,
                provider
            )
        );

        vm.prank(provider);
        claimPay.disputeMilestone(agreementId, 0);
    }

    function testRevertWhenDisputingMilestoneFromUnknownAgreement() public {
        vm.expectRevert(
            abi.encodeWithSelector(ClaimPay.AgreementNotFound.selector, 1)
        );

        vm.prank(client);
        claimPay.disputeMilestone(1, 0);

        assertEq(claimPay.agreementCount(), 0);
    }
    function testRevertWhenDisputingMilestoneDoesNotExist() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Maquette";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            arbiter,
            descriptions,
            amounts
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ClaimPay.MilestoneNotFound.selector,
                agreementId,
                1
            )
        );

        vm.prank(client);
        claimPay.disputeMilestone(agreementId, 1);
    }
    function testRevertWhenDisputingPendingMilestone() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Maquette";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            arbiter,
            descriptions,
            amounts
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ClaimPay.InvalidMilestoneStatus.selector,
                agreementId,
                0,
                ClaimPay.MilestoneStatus.Pending
            )
        );

        vm.prank(client);
        claimPay.disputeMilestone(agreementId, 0);

        (, , ClaimPay.MilestoneStatus storedStatus) = claimPay.getMilestone(
            agreementId,
            0
        );

        assertEq(
            uint256(storedStatus),
            uint256(ClaimPay.MilestoneStatus.Pending)
        );
    }

    function testRevertWhenDisputingMilestoneTwice() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Maquette";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            arbiter,
            descriptions,
            amounts
        );

        vm.prank(provider);
        claimPay.submitMilestone(agreementId, 0);

        vm.prank(client);
        claimPay.disputeMilestone(agreementId, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                ClaimPay.InvalidMilestoneStatus.selector,
                agreementId,
                0,
                ClaimPay.MilestoneStatus.Disputed
            )
        );

        vm.prank(client);
        claimPay.disputeMilestone(agreementId, 0);

        (, , ClaimPay.MilestoneStatus storedStatus) = claimPay.getMilestone(
            agreementId,
            0
        );

        assertEq(
            uint256(storedStatus),
            uint256(ClaimPay.MilestoneStatus.Disputed)
        );
    }

    function testRevertWhenDisputingPaidMilestone() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Maquette";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            arbiter,
            descriptions,
            amounts
        );

        vm.prank(provider);
        claimPay.submitMilestone(agreementId, 0);

        vm.prank(client);
        claimPay.approveMilestone(agreementId, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                ClaimPay.InvalidMilestoneStatus.selector,
                agreementId,
                0,
                ClaimPay.MilestoneStatus.Paid
            )
        );

        vm.prank(client);
        claimPay.disputeMilestone(agreementId, 0);

        (, , ClaimPay.MilestoneStatus storedStatus) = claimPay.getMilestone(
            agreementId,
            0
        );

        assertEq(uint256(storedStatus), uint256(ClaimPay.MilestoneStatus.Paid));
    }

    function testEmitMilestoneDisputed() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Maquette";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            arbiter,
            descriptions,
            amounts
        );

        vm.prank(provider);
        claimPay.submitMilestone(agreementId, 0);

        vm.expectEmit(true, true, true, true, address(claimPay));
        emit MilestoneDisputed(agreementId, 0, client);

        vm.prank(client);
        claimPay.disputeMilestone(agreementId, 0);
    }

    function testResolverCanPayProviderAfterDispute() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Maquette";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            arbiter,
            descriptions,
            amounts
        );

        vm.prank(provider);
        claimPay.submitMilestone(agreementId, 0);

        vm.prank(client);
        claimPay.disputeMilestone(agreementId, 0);

        uint256 providerBalanceBefore = mockUSDC.balanceOf(provider);
        uint256 clientBalanceBefore = mockUSDC.balanceOf(client);
        uint256 claimPayBalanceBefore = mockUSDC.balanceOf(address(claimPay));

        vm.prank(arbiter);
        claimPay.resolveDispute(
            agreementId,
            0,
            ClaimPay.DisputeResolution.PayProvider
        );

        (, , ClaimPay.MilestoneStatus milestoneStatus) = claimPay.getMilestone(
            agreementId,
            0
        );

        (, , , ClaimPay.AgreementStatus agreementStatus, ) = claimPay
            .getAgreement(agreementId);

        assertEq(
            uint256(milestoneStatus),
            uint256(ClaimPay.MilestoneStatus.Paid)
        );

        assertEq(
            uint256(agreementStatus),
            uint256(ClaimPay.AgreementStatus.Completed)
        );

        assertEq(
            mockUSDC.balanceOf(provider),
            providerBalanceBefore + amounts[0]
        );

        assertEq(mockUSDC.balanceOf(client), clientBalanceBefore);

        assertEq(
            mockUSDC.balanceOf(address(claimPay)),
            claimPayBalanceBefore - amounts[0]
        );
    }

    function testResolverCanRefundClientAfterDispute() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Maquette";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            arbiter,
            descriptions,
            amounts
        );

        vm.prank(provider);
        claimPay.submitMilestone(agreementId, 0);

        vm.prank(client);
        claimPay.disputeMilestone(agreementId, 0);

        uint256 providerBalanceBefore = mockUSDC.balanceOf(provider);
        uint256 clientBalanceBefore = mockUSDC.balanceOf(client);
        uint256 claimPayBalanceBefore = mockUSDC.balanceOf(address(claimPay));

        vm.prank(arbiter);
        claimPay.resolveDispute(
            agreementId,
            0,
            ClaimPay.DisputeResolution.RefundClient
        );

        (, , ClaimPay.MilestoneStatus milestoneStatus) = claimPay.getMilestone(
            agreementId,
            0
        );

        (, , , ClaimPay.AgreementStatus agreementStatus, ) = claimPay
            .getAgreement(agreementId);

        assertEq(
            uint256(milestoneStatus),
            uint256(ClaimPay.MilestoneStatus.Refunded)
        );

        assertEq(
            uint256(agreementStatus),
            uint256(ClaimPay.AgreementStatus.Completed)
        );

        assertEq(mockUSDC.balanceOf(provider), providerBalanceBefore);

        assertEq(mockUSDC.balanceOf(client), clientBalanceBefore + amounts[0]);

        assertEq(
            mockUSDC.balanceOf(address(claimPay)),
            claimPayBalanceBefore - amounts[0]
        );
    }

    function testRevertWhenResolverIsNotConfigured() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Maquette";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            address(0),
            descriptions,
            amounts
        );

        vm.prank(provider);
        claimPay.submitMilestone(agreementId, 0);

        vm.prank(client);
        claimPay.disputeMilestone(agreementId, 0);

        uint256 claimPayBalanceBefore = mockUSDC.balanceOf(address(claimPay));

        vm.expectRevert(
            abi.encodeWithSelector(
                ClaimPay.NoDisputeResolverConfigured.selector,
                agreementId
            )
        );

        vm.prank(arbiter);
        claimPay.resolveDispute(
            agreementId,
            0,
            ClaimPay.DisputeResolution.PayProvider
        );

        (, , ClaimPay.MilestoneStatus storedStatus) = claimPay.getMilestone(
            agreementId,
            0
        );

        assertEq(
            uint256(storedStatus),
            uint256(ClaimPay.MilestoneStatus.Disputed)
        );

        assertEq(mockUSDC.balanceOf(address(claimPay)), claimPayBalanceBefore);
    }

    function testRevertWhenNonResolverResolvesDispute() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Maquette";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            arbiter,
            descriptions,
            amounts
        );

        vm.prank(provider);
        claimPay.submitMilestone(agreementId, 0);

        vm.prank(client);
        claimPay.disputeMilestone(agreementId, 0);

        uint256 claimPayBalanceBefore = mockUSDC.balanceOf(address(claimPay));

        vm.expectRevert(
            abi.encodeWithSelector(
                ClaimPay.NotAgreementResolver.selector,
                agreementId,
                client
            )
        );

        vm.prank(client);
        claimPay.resolveDispute(
            agreementId,
            0,
            ClaimPay.DisputeResolution.RefundClient
        );

        (, , ClaimPay.MilestoneStatus storedStatus) = claimPay.getMilestone(
            agreementId,
            0
        );

        assertEq(
            uint256(storedStatus),
            uint256(ClaimPay.MilestoneStatus.Disputed)
        );

        assertEq(mockUSDC.balanceOf(address(claimPay)), claimPayBalanceBefore);
    }

    function testRevertWhenResolvingUnknownAgreement() public {
        vm.expectRevert(
            abi.encodeWithSelector(ClaimPay.AgreementNotFound.selector, 1)
        );

        vm.prank(arbiter);
        claimPay.resolveDispute(1, 0, ClaimPay.DisputeResolution.PayProvider);

        assertEq(claimPay.agreementCount(), 0);
    }

    function testRevertWhenResolvingMilestoneDoesNotExist() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Maquette";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            arbiter,
            descriptions,
            amounts
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ClaimPay.MilestoneNotFound.selector,
                agreementId,
                1
            )
        );

        vm.prank(arbiter);
        claimPay.resolveDispute(
            agreementId,
            1,
            ClaimPay.DisputeResolution.PayProvider
        );
    }

    function testRevertWhenResolvingSubmittedMilestone() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Maquette";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            arbiter,
            descriptions,
            amounts
        );

        vm.prank(provider);
        claimPay.submitMilestone(agreementId, 0);

        uint256 claimPayBalanceBefore = mockUSDC.balanceOf(address(claimPay));

        vm.expectRevert(
            abi.encodeWithSelector(
                ClaimPay.InvalidMilestoneStatus.selector,
                agreementId,
                0,
                ClaimPay.MilestoneStatus.Submitted
            )
        );

        vm.prank(arbiter);
        claimPay.resolveDispute(
            agreementId,
            0,
            ClaimPay.DisputeResolution.PayProvider
        );

        (, , ClaimPay.MilestoneStatus storedStatus) = claimPay.getMilestone(
            agreementId,
            0
        );

        assertEq(
            uint256(storedStatus),
            uint256(ClaimPay.MilestoneStatus.Submitted)
        );

        assertEq(mockUSDC.balanceOf(address(claimPay)), claimPayBalanceBefore);
    }

    function testRevertWhenResolvingDisputeTwice() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Maquette";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            arbiter,
            descriptions,
            amounts
        );

        vm.prank(provider);
        claimPay.submitMilestone(agreementId, 0);

        vm.prank(client);
        claimPay.disputeMilestone(agreementId, 0);

        vm.prank(arbiter);
        claimPay.resolveDispute(
            agreementId,
            0,
            ClaimPay.DisputeResolution.PayProvider
        );

        uint256 providerBalanceAfterFirstResolution = mockUSDC.balanceOf(
            provider
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ClaimPay.InvalidMilestoneStatus.selector,
                agreementId,
                0,
                ClaimPay.MilestoneStatus.Paid
            )
        );

        vm.prank(arbiter);
        claimPay.resolveDispute(
            agreementId,
            0,
            ClaimPay.DisputeResolution.RefundClient
        );

        (, , ClaimPay.MilestoneStatus storedStatus) = claimPay.getMilestone(
            agreementId,
            0
        );

        assertEq(uint256(storedStatus), uint256(ClaimPay.MilestoneStatus.Paid));

        assertEq(
            mockUSDC.balanceOf(provider),
            providerBalanceAfterFirstResolution
        );
    }

    function testAgreementCompletesAfterPaidAndRefundedMilestones() public {
        string[] memory descriptions = new string[](2);
        descriptions[0] = "Maquette";
        descriptions[1] = "Developpement";

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 500 * 10 ** 6;
        amounts[1] = 1_000 * 10 ** 6;

        uint256 clientBalanceBefore = mockUSDC.balanceOf(client);
        uint256 providerBalanceBefore = mockUSDC.balanceOf(provider);

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            arbiter,
            descriptions,
            amounts
        );

        vm.prank(provider);
        claimPay.submitMilestone(agreementId, 0);

        vm.prank(client);
        claimPay.approveMilestone(agreementId, 0);

        (, , , ClaimPay.AgreementStatus statusAfterFirstMilestone, ) = claimPay
            .getAgreement(agreementId);

        assertEq(
            uint256(statusAfterFirstMilestone),
            uint256(ClaimPay.AgreementStatus.Active)
        );

        vm.prank(provider);
        claimPay.submitMilestone(agreementId, 1);

        vm.prank(client);
        claimPay.disputeMilestone(agreementId, 1);

        vm.prank(arbiter);
        claimPay.resolveDispute(
            agreementId,
            1,
            ClaimPay.DisputeResolution.RefundClient
        );

        (, , ClaimPay.MilestoneStatus firstMilestoneStatus) = claimPay
            .getMilestone(agreementId, 0);

        (, , ClaimPay.MilestoneStatus secondMilestoneStatus) = claimPay
            .getMilestone(agreementId, 1);

        (, , , ClaimPay.AgreementStatus finalAgreementStatus, ) = claimPay
            .getAgreement(agreementId);

        assertEq(
            uint256(firstMilestoneStatus),
            uint256(ClaimPay.MilestoneStatus.Paid)
        );

        assertEq(
            uint256(secondMilestoneStatus),
            uint256(ClaimPay.MilestoneStatus.Refunded)
        );

        assertEq(
            uint256(finalAgreementStatus),
            uint256(ClaimPay.AgreementStatus.Completed)
        );

        assertEq(
            mockUSDC.balanceOf(provider),
            providerBalanceBefore + amounts[0]
        );

        assertEq(mockUSDC.balanceOf(client), clientBalanceBefore - amounts[0]);

        assertEq(mockUSDC.balanceOf(address(claimPay)), 0);
    }

    function testEmitRefundAndDisputeResolutionEvents() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Maquette";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            arbiter,
            descriptions,
            amounts
        );

        vm.prank(provider);
        claimPay.submitMilestone(agreementId, 0);

        vm.prank(client);
        claimPay.disputeMilestone(agreementId, 0);

        vm.expectEmit(true, true, true, true, address(claimPay));
        emit MilestoneRefunded(agreementId, 0, client, amounts[0]);

        vm.expectEmit(true, true, true, true, address(claimPay));
        emit DisputeResolved(
            agreementId,
            0,
            arbiter,
            ClaimPay.DisputeResolution.RefundClient
        );

        vm.expectEmit(true, false, false, true, address(claimPay));
        emit AgreementCompleted(agreementId);

        vm.prank(arbiter);
        claimPay.resolveDispute(
            agreementId,
            0,
            ClaimPay.DisputeResolution.RefundClient
        );
    }
    function testClientCanProposeRefundAndProviderCanAccept() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Maquette";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            address(0),
            descriptions,
            amounts
        );

        vm.prank(provider);
        claimPay.submitMilestone(agreementId, 0);

        vm.prank(client);
        claimPay.disputeMilestone(agreementId, 0);

        vm.prank(client);
        claimPay.proposeSettlement(
            agreementId,
            0,
            ClaimPay.DisputeResolution.RefundClient
        );

        (
            bool proposalExists,
            address proposalAuthor,
            ClaimPay.DisputeResolution proposedResolution
        ) = claimPay.getSettlementProposal(agreementId, 0);

        assertTrue(proposalExists);
        assertEq(proposalAuthor, client);
        assertEq(
            uint256(proposedResolution),
            uint256(ClaimPay.DisputeResolution.RefundClient)
        );

        uint256 clientBalanceBefore = mockUSDC.balanceOf(client);
        uint256 providerBalanceBefore = mockUSDC.balanceOf(provider);

        vm.prank(provider);
        claimPay.acceptSettlement(
            agreementId,
            0,
            ClaimPay.DisputeResolution.RefundClient
        );

        (, , ClaimPay.MilestoneStatus milestoneStatus) = claimPay.getMilestone(
            agreementId,
            0
        );

        (, , , ClaimPay.AgreementStatus agreementStatus, ) = claimPay
            .getAgreement(agreementId);

        (bool proposalExistsAfter, address proposalAuthorAfter, ) = claimPay
            .getSettlementProposal(agreementId, 0);

        assertEq(
            uint256(milestoneStatus),
            uint256(ClaimPay.MilestoneStatus.Refunded)
        );

        assertEq(
            uint256(agreementStatus),
            uint256(ClaimPay.AgreementStatus.Completed)
        );

        assertEq(mockUSDC.balanceOf(client), clientBalanceBefore + amounts[0]);

        assertEq(mockUSDC.balanceOf(provider), providerBalanceBefore);
        assertEq(mockUSDC.balanceOf(address(claimPay)), 0);

        assertFalse(proposalExistsAfter);
        assertEq(proposalAuthorAfter, address(0));
    }
    function testProviderCanProposePaymentAndClientCanAccept() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Developpement";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 750 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            address(0),
            descriptions,
            amounts
        );

        vm.prank(provider);
        claimPay.submitMilestone(agreementId, 0);

        vm.prank(client);
        claimPay.disputeMilestone(agreementId, 0);

        vm.prank(provider);
        claimPay.proposeSettlement(
            agreementId,
            0,
            ClaimPay.DisputeResolution.PayProvider
        );

        (
            bool proposalExists,
            address proposalAuthor,
            ClaimPay.DisputeResolution proposedResolution
        ) = claimPay.getSettlementProposal(agreementId, 0);

        assertTrue(proposalExists);
        assertEq(proposalAuthor, provider);
        assertEq(
            uint256(proposedResolution),
            uint256(ClaimPay.DisputeResolution.PayProvider)
        );

        uint256 clientBalanceBefore = mockUSDC.balanceOf(client);
        uint256 providerBalanceBefore = mockUSDC.balanceOf(provider);

        vm.prank(client);
        claimPay.acceptSettlement(
            agreementId,
            0,
            ClaimPay.DisputeResolution.PayProvider
        );

        (, , ClaimPay.MilestoneStatus milestoneStatus) = claimPay.getMilestone(
            agreementId,
            0
        );

        (, , , ClaimPay.AgreementStatus agreementStatus, ) = claimPay
            .getAgreement(agreementId);

        (bool proposalExistsAfter, address proposalAuthorAfter, ) = claimPay
            .getSettlementProposal(agreementId, 0);

        assertEq(
            uint256(milestoneStatus),
            uint256(ClaimPay.MilestoneStatus.Paid)
        );

        assertEq(
            uint256(agreementStatus),
            uint256(ClaimPay.AgreementStatus.Completed)
        );

        assertEq(mockUSDC.balanceOf(client), clientBalanceBefore);

        assertEq(
            mockUSDC.balanceOf(provider),
            providerBalanceBefore + amounts[0]
        );

        assertEq(mockUSDC.balanceOf(address(claimPay)), 0);

        assertFalse(proposalExistsAfter);
        assertEq(proposalAuthorAfter, address(0));
    }
    function testSettlementProposalCanBeReplaced() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Integration";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 600 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            address(0),
            descriptions,
            amounts
        );

        vm.prank(provider);
        claimPay.submitMilestone(agreementId, 0);

        vm.prank(client);
        claimPay.disputeMilestone(agreementId, 0);

        vm.prank(client);
        claimPay.proposeSettlement(
            agreementId,
            0,
            ClaimPay.DisputeResolution.RefundClient
        );

        vm.prank(provider);
        claimPay.proposeSettlement(
            agreementId,
            0,
            ClaimPay.DisputeResolution.PayProvider
        );

        (
            bool proposalExists,
            address proposalAuthor,
            ClaimPay.DisputeResolution proposedResolution
        ) = claimPay.getSettlementProposal(agreementId, 0);

        (, , ClaimPay.MilestoneStatus milestoneStatus) = claimPay.getMilestone(
            agreementId,
            0
        );

        assertTrue(proposalExists);
        assertEq(proposalAuthor, provider);

        assertEq(
            uint256(proposedResolution),
            uint256(ClaimPay.DisputeResolution.PayProvider)
        );

        assertEq(
            uint256(milestoneStatus),
            uint256(ClaimPay.MilestoneStatus.Disputed)
        );

        assertEq(mockUSDC.balanceOf(address(claimPay)), amounts[0]);

        assertEq(mockUSDC.balanceOf(provider), 0);
    }
    function testRevertWhenNonPartyProposesSettlement() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Audit";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 400 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            address(0),
            descriptions,
            amounts
        );

        vm.prank(provider);
        claimPay.submitMilestone(agreementId, 0);

        vm.prank(client);
        claimPay.disputeMilestone(agreementId, 0);

        address outsider = makeAddr("outsider");

        vm.expectRevert(
            abi.encodeWithSelector(
                ClaimPay.NotAgreementParty.selector,
                agreementId,
                outsider
            )
        );

        vm.prank(outsider);
        claimPay.proposeSettlement(
            agreementId,
            0,
            ClaimPay.DisputeResolution.PayProvider
        );

        (
            bool proposalExists,
            address proposalAuthor,
            ClaimPay.DisputeResolution proposedResolution
        ) = claimPay.getSettlementProposal(agreementId, 0);

        (, , ClaimPay.MilestoneStatus milestoneStatus) = claimPay.getMilestone(
            agreementId,
            0
        );

        assertFalse(proposalExists);
        assertEq(proposalAuthor, address(0));

        assertEq(
            uint256(proposedResolution),
            uint256(ClaimPay.DisputeResolution.PayProvider)
        );

        assertEq(
            uint256(milestoneStatus),
            uint256(ClaimPay.MilestoneStatus.Disputed)
        );

        assertEq(mockUSDC.balanceOf(address(claimPay)), amounts[0]);
    }
    function testRevertWhenNonPartyAcceptsSettlement() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Application";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 800 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            address(0),
            descriptions,
            amounts
        );

        vm.prank(provider);
        claimPay.submitMilestone(agreementId, 0);

        vm.prank(client);
        claimPay.disputeMilestone(agreementId, 0);

        vm.prank(client);
        claimPay.proposeSettlement(
            agreementId,
            0,
            ClaimPay.DisputeResolution.RefundClient
        );

        address outsider = makeAddr("outsider");

        vm.expectRevert(
            abi.encodeWithSelector(
                ClaimPay.NotAgreementParty.selector,
                agreementId,
                outsider
            )
        );

        vm.prank(outsider);
        claimPay.acceptSettlement(
            agreementId,
            0,
            ClaimPay.DisputeResolution.RefundClient
        );

        (
            bool proposalExists,
            address proposalAuthor,
            ClaimPay.DisputeResolution proposedResolution
        ) = claimPay.getSettlementProposal(agreementId, 0);

        (, , ClaimPay.MilestoneStatus milestoneStatus) = claimPay.getMilestone(
            agreementId,
            0
        );

        assertTrue(proposalExists);
        assertEq(proposalAuthor, client);

        assertEq(
            uint256(proposedResolution),
            uint256(ClaimPay.DisputeResolution.RefundClient)
        );

        assertEq(
            uint256(milestoneStatus),
            uint256(ClaimPay.MilestoneStatus.Disputed)
        );

        assertEq(mockUSDC.balanceOf(address(claimPay)), amounts[0]);

        assertEq(mockUSDC.balanceOf(provider), 0);
    }
    function testRevertWhenProposingSettlementWithResolverConfigured() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Interface";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 550 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            arbiter,
            descriptions,
            amounts
        );

        vm.prank(provider);
        claimPay.submitMilestone(agreementId, 0);

        vm.prank(client);
        claimPay.disputeMilestone(agreementId, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                ClaimPay.DisputeResolverAlreadyConfigured.selector,
                agreementId
            )
        );

        vm.prank(client);
        claimPay.proposeSettlement(
            agreementId,
            0,
            ClaimPay.DisputeResolution.RefundClient
        );

        (
            bool proposalExists,
            address proposalAuthor,
            ClaimPay.DisputeResolution proposedResolution
        ) = claimPay.getSettlementProposal(agreementId, 0);

        (, , ClaimPay.MilestoneStatus milestoneStatus) = claimPay.getMilestone(
            agreementId,
            0
        );

        assertFalse(proposalExists);
        assertEq(proposalAuthor, address(0));

        assertEq(
            uint256(proposedResolution),
            uint256(ClaimPay.DisputeResolution.PayProvider)
        );

        assertEq(
            uint256(milestoneStatus),
            uint256(ClaimPay.MilestoneStatus.Disputed)
        );

        assertEq(mockUSDC.balanceOf(address(claimPay)), amounts[0]);
    }

    function testRevertWhenAcceptingSettlementWithResolverConfigured() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Prototype";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 650 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            arbiter,
            descriptions,
            amounts
        );

        vm.prank(provider);
        claimPay.submitMilestone(agreementId, 0);

        vm.prank(client);
        claimPay.disputeMilestone(agreementId, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                ClaimPay.DisputeResolverAlreadyConfigured.selector,
                agreementId
            )
        );

        vm.prank(provider);
        claimPay.acceptSettlement(
            agreementId,
            0,
            ClaimPay.DisputeResolution.RefundClient
        );

        (, , ClaimPay.MilestoneStatus milestoneStatus) = claimPay.getMilestone(
            agreementId,
            0
        );

        assertEq(
            uint256(milestoneStatus),
            uint256(ClaimPay.MilestoneStatus.Disputed)
        );

        assertEq(mockUSDC.balanceOf(address(claimPay)), amounts[0]);

        assertEq(mockUSDC.balanceOf(provider), 0);
    }
    function testRevertWhenProposingSettlementForUnknownAgreement() public {
        uint256 unknownAgreementId = 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                ClaimPay.AgreementNotFound.selector,
                unknownAgreementId
            )
        );

        vm.prank(client);
        claimPay.proposeSettlement(
            unknownAgreementId,
            0,
            ClaimPay.DisputeResolution.RefundClient
        );

        assertEq(claimPay.agreementCount(), 0);
    }

    function testRevertWhenAcceptingSettlementForUnknownAgreement() public {
        uint256 unknownAgreementId = 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                ClaimPay.AgreementNotFound.selector,
                unknownAgreementId
            )
        );

        vm.prank(provider);
        claimPay.acceptSettlement(
            unknownAgreementId,
            0,
            ClaimPay.DisputeResolution.PayProvider
        );

        assertEq(claimPay.agreementCount(), 0);
    }

    function testRevertWhenProposingSettlementForUnknownMilestone() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Design";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 300 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            address(0),
            descriptions,
            amounts
        );

        uint256 unknownMilestoneIndex = 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                ClaimPay.MilestoneNotFound.selector,
                agreementId,
                unknownMilestoneIndex
            )
        );

        vm.prank(client);
        claimPay.proposeSettlement(
            agreementId,
            unknownMilestoneIndex,
            ClaimPay.DisputeResolution.RefundClient
        );

        assertEq(mockUSDC.balanceOf(address(claimPay)), amounts[0]);
    }
    function testRevertWhenAcceptingSettlementForUnknownMilestone() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Backend";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 450 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            address(0),
            descriptions,
            amounts
        );

        uint256 unknownMilestoneIndex = 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                ClaimPay.MilestoneNotFound.selector,
                agreementId,
                unknownMilestoneIndex
            )
        );

        vm.prank(provider);
        claimPay.acceptSettlement(
            agreementId,
            unknownMilestoneIndex,
            ClaimPay.DisputeResolution.PayProvider
        );

        assertEq(mockUSDC.balanceOf(address(claimPay)), amounts[0]);
    }
    function testRevertWhenProposingSettlementForPendingMilestone() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Specification";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 350 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            address(0),
            descriptions,
            amounts
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ClaimPay.InvalidMilestoneStatus.selector,
                agreementId,
                0,
                ClaimPay.MilestoneStatus.Pending
            )
        );

        vm.prank(client);
        claimPay.proposeSettlement(
            agreementId,
            0,
            ClaimPay.DisputeResolution.RefundClient
        );

        (
            bool proposalExists,
            address proposalAuthor,
            ClaimPay.DisputeResolution proposedResolution
        ) = claimPay.getSettlementProposal(agreementId, 0);

        (, , ClaimPay.MilestoneStatus milestoneStatus) = claimPay.getMilestone(
            agreementId,
            0
        );

        assertFalse(proposalExists);
        assertEq(proposalAuthor, address(0));

        assertEq(
            uint256(proposedResolution),
            uint256(ClaimPay.DisputeResolution.PayProvider)
        );

        assertEq(
            uint256(milestoneStatus),
            uint256(ClaimPay.MilestoneStatus.Pending)
        );

        assertEq(mockUSDC.balanceOf(address(claimPay)), amounts[0]);
    }
    function testRevertWhenProposingSettlementForSubmittedMilestone() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Livraison";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            address(0),
            descriptions,
            amounts
        );

        vm.prank(provider);
        claimPay.submitMilestone(agreementId, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                ClaimPay.InvalidMilestoneStatus.selector,
                agreementId,
                0,
                ClaimPay.MilestoneStatus.Submitted
            )
        );

        vm.prank(provider);
        claimPay.proposeSettlement(
            agreementId,
            0,
            ClaimPay.DisputeResolution.PayProvider
        );

        (
            bool proposalExists,
            address proposalAuthor,
            ClaimPay.DisputeResolution proposedResolution
        ) = claimPay.getSettlementProposal(agreementId, 0);

        (, , ClaimPay.MilestoneStatus milestoneStatus) = claimPay.getMilestone(
            agreementId,
            0
        );

        assertFalse(proposalExists);
        assertEq(proposalAuthor, address(0));

        assertEq(
            uint256(proposedResolution),
            uint256(ClaimPay.DisputeResolution.PayProvider)
        );

        assertEq(
            uint256(milestoneStatus),
            uint256(ClaimPay.MilestoneStatus.Submitted)
        );

        assertEq(mockUSDC.balanceOf(address(claimPay)), amounts[0]);
    }
    function testRevertWhenAcceptingSettlementWithoutProposal() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Validation";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 700 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            address(0),
            descriptions,
            amounts
        );

        vm.prank(provider);
        claimPay.submitMilestone(agreementId, 0);

        vm.prank(client);
        claimPay.disputeMilestone(agreementId, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                ClaimPay.SettlementProposalNotFound.selector,
                agreementId,
                0
            )
        );

        vm.prank(provider);
        claimPay.acceptSettlement(
            agreementId,
            0,
            ClaimPay.DisputeResolution.RefundClient
        );

        (
            bool proposalExists,
            address proposalAuthor,
            ClaimPay.DisputeResolution proposedResolution
        ) = claimPay.getSettlementProposal(agreementId, 0);

        (, , ClaimPay.MilestoneStatus milestoneStatus) = claimPay.getMilestone(
            agreementId,
            0
        );

        assertFalse(proposalExists);
        assertEq(proposalAuthor, address(0));

        assertEq(
            uint256(proposedResolution),
            uint256(ClaimPay.DisputeResolution.PayProvider)
        );

        assertEq(
            uint256(milestoneStatus),
            uint256(ClaimPay.MilestoneStatus.Disputed)
        );

        assertEq(mockUSDC.balanceOf(address(claimPay)), amounts[0]);

        assertEq(mockUSDC.balanceOf(provider), 0);
    }
    function testRevertWhenProposerAcceptsOwnSettlement() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Recette";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 900 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            address(0),
            descriptions,
            amounts
        );

        vm.prank(provider);
        claimPay.submitMilestone(agreementId, 0);

        vm.prank(client);
        claimPay.disputeMilestone(agreementId, 0);

        vm.prank(client);
        claimPay.proposeSettlement(
            agreementId,
            0,
            ClaimPay.DisputeResolution.RefundClient
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ClaimPay.SettlementProposerCannotAccept.selector,
                agreementId,
                0
            )
        );

        vm.prank(client);
        claimPay.acceptSettlement(
            agreementId,
            0,
            ClaimPay.DisputeResolution.RefundClient
        );

        (
            bool proposalExists,
            address proposalAuthor,
            ClaimPay.DisputeResolution proposedResolution
        ) = claimPay.getSettlementProposal(agreementId, 0);

        (, , ClaimPay.MilestoneStatus milestoneStatus) = claimPay.getMilestone(
            agreementId,
            0
        );

        assertTrue(proposalExists);
        assertEq(proposalAuthor, client);

        assertEq(
            uint256(proposedResolution),
            uint256(ClaimPay.DisputeResolution.RefundClient)
        );

        assertEq(
            uint256(milestoneStatus),
            uint256(ClaimPay.MilestoneStatus.Disputed)
        );

        assertEq(mockUSDC.balanceOf(address(claimPay)), amounts[0]);

        assertEq(mockUSDC.balanceOf(provider), 0);
    }
    function testRevertWhenAcceptedResolutionDoesNotMatchProposal() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Correction";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 625 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            address(0),
            descriptions,
            amounts
        );

        vm.prank(provider);
        claimPay.submitMilestone(agreementId, 0);

        vm.prank(client);
        claimPay.disputeMilestone(agreementId, 0);

        vm.prank(client);
        claimPay.proposeSettlement(
            agreementId,
            0,
            ClaimPay.DisputeResolution.RefundClient
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ClaimPay.SettlementProposalMismatch.selector,
                agreementId,
                0,
                ClaimPay.DisputeResolution.PayProvider,
                ClaimPay.DisputeResolution.RefundClient
            )
        );

        vm.prank(provider);
        claimPay.acceptSettlement(
            agreementId,
            0,
            ClaimPay.DisputeResolution.PayProvider
        );

        (
            bool proposalExists,
            address proposalAuthor,
            ClaimPay.DisputeResolution proposedResolution
        ) = claimPay.getSettlementProposal(agreementId, 0);

        (, , ClaimPay.MilestoneStatus milestoneStatus) = claimPay.getMilestone(
            agreementId,
            0
        );

        assertTrue(proposalExists);
        assertEq(proposalAuthor, client);

        assertEq(
            uint256(proposedResolution),
            uint256(ClaimPay.DisputeResolution.RefundClient)
        );

        assertEq(
            uint256(milestoneStatus),
            uint256(ClaimPay.MilestoneStatus.Disputed)
        );

        assertEq(mockUSDC.balanceOf(address(claimPay)), amounts[0]);

        assertEq(mockUSDC.balanceOf(provider), 0);
    }
    function testRevertWhenAcceptingSettlementTwice() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Deploiement";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 475 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            address(0),
            descriptions,
            amounts
        );

        vm.prank(provider);
        claimPay.submitMilestone(agreementId, 0);

        vm.prank(client);
        claimPay.disputeMilestone(agreementId, 0);

        vm.prank(client);
        claimPay.proposeSettlement(
            agreementId,
            0,
            ClaimPay.DisputeResolution.RefundClient
        );

        vm.prank(provider);
        claimPay.acceptSettlement(
            agreementId,
            0,
            ClaimPay.DisputeResolution.RefundClient
        );

        uint256 clientBalanceAfterFirstAcceptance = mockUSDC.balanceOf(client);
        uint256 providerBalanceAfterFirstAcceptance = mockUSDC.balanceOf(
            provider
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ClaimPay.InvalidMilestoneStatus.selector,
                agreementId,
                0,
                ClaimPay.MilestoneStatus.Refunded
            )
        );

        vm.prank(provider);
        claimPay.acceptSettlement(
            agreementId,
            0,
            ClaimPay.DisputeResolution.RefundClient
        );

        (, , ClaimPay.MilestoneStatus milestoneStatus) = claimPay.getMilestone(
            agreementId,
            0
        );

        (, , , ClaimPay.AgreementStatus agreementStatus, ) = claimPay
            .getAgreement(agreementId);

        (bool proposalExists, address proposalAuthor, ) = claimPay
            .getSettlementProposal(agreementId, 0);

        assertEq(
            uint256(milestoneStatus),
            uint256(ClaimPay.MilestoneStatus.Refunded)
        );

        assertEq(
            uint256(agreementStatus),
            uint256(ClaimPay.AgreementStatus.Completed)
        );

        assertEq(mockUSDC.balanceOf(client), clientBalanceAfterFirstAcceptance);

        assertEq(
            mockUSDC.balanceOf(provider),
            providerBalanceAfterFirstAcceptance
        );

        assertEq(mockUSDC.balanceOf(address(claimPay)), 0);

        assertFalse(proposalExists);
        assertEq(proposalAuthor, address(0));
    }

    function testRevertWhenGettingSettlementProposalFromUnknownAgreement()
        public
    {
        uint256 unknownAgreementId = 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                ClaimPay.AgreementNotFound.selector,
                unknownAgreementId
            )
        );

        claimPay.getSettlementProposal(unknownAgreementId, 0);
    }

    function testRevertWhenGettingSettlementProposalFromUnknownMilestone()
        public
    {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Maintenance";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 275 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            address(0),
            descriptions,
            amounts
        );

        uint256 unknownMilestoneIndex = 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                ClaimPay.MilestoneNotFound.selector,
                agreementId,
                unknownMilestoneIndex
            )
        );

        claimPay.getSettlementProposal(agreementId, unknownMilestoneIndex);
    }
    function testEmitSettlementProposed() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Documentation";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 525 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            address(0),
            descriptions,
            amounts
        );

        vm.prank(provider);
        claimPay.submitMilestone(agreementId, 0);

        vm.prank(client);
        claimPay.disputeMilestone(agreementId, 0);

        vm.expectEmit(true, true, true, true, address(claimPay));

        emit SettlementProposed(
            agreementId,
            0,
            client,
            ClaimPay.DisputeResolution.RefundClient
        );

        vm.prank(client);
        claimPay.proposeSettlement(
            agreementId,
            0,
            ClaimPay.DisputeResolution.RefundClient
        );
    }

    function testEmitSettlementAcceptedAndRefundEvents() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Formation";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 575 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            address(0),
            descriptions,
            amounts
        );

        vm.prank(provider);
        claimPay.submitMilestone(agreementId, 0);

        vm.prank(client);
        claimPay.disputeMilestone(agreementId, 0);

        vm.prank(client);
        claimPay.proposeSettlement(
            agreementId,
            0,
            ClaimPay.DisputeResolution.RefundClient
        );

        vm.expectEmit(true, true, true, true, address(claimPay));

        emit MilestoneRefunded(agreementId, 0, client, amounts[0]);

        vm.expectEmit(true, true, true, true, address(claimPay));

        emit SettlementAccepted(
            agreementId,
            0,
            provider,
            ClaimPay.DisputeResolution.RefundClient
        );

        vm.expectEmit(true, false, false, false, address(claimPay));

        emit AgreementCompleted(agreementId);

        vm.prank(provider);
        claimPay.acceptSettlement(
            agreementId,
            0,
            ClaimPay.DisputeResolution.RefundClient
        );
    }

    function testAgreementCompletesAfterDirectPaymentAndMutualRefund() public {
        string[] memory descriptions = new string[](2);
        descriptions[0] = "Conception";
        descriptions[1] = "Developpement";

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 400 * 10 ** 6;
        amounts[1] = 600 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            address(0),
            descriptions,
            amounts
        );

        uint256 clientBalanceAfterFunding = mockUSDC.balanceOf(client);
        uint256 providerBalanceBefore = mockUSDC.balanceOf(provider);

        vm.prank(provider);
        claimPay.submitMilestone(agreementId, 0);

        vm.prank(client);
        claimPay.approveMilestone(agreementId, 0);

        (, , ClaimPay.MilestoneStatus firstMilestoneStatus) = claimPay
            .getMilestone(agreementId, 0);

        (, , , ClaimPay.AgreementStatus statusAfterFirstMilestone, ) = claimPay
            .getAgreement(agreementId);

        assertEq(
            uint256(firstMilestoneStatus),
            uint256(ClaimPay.MilestoneStatus.Paid)
        );

        assertEq(
            uint256(statusAfterFirstMilestone),
            uint256(ClaimPay.AgreementStatus.Active)
        );

        assertEq(
            mockUSDC.balanceOf(provider),
            providerBalanceBefore + amounts[0]
        );

        assertEq(mockUSDC.balanceOf(address(claimPay)), amounts[1]);

        vm.prank(provider);
        claimPay.submitMilestone(agreementId, 1);

        vm.prank(client);
        claimPay.disputeMilestone(agreementId, 1);

        vm.prank(client);
        claimPay.proposeSettlement(
            agreementId,
            1,
            ClaimPay.DisputeResolution.RefundClient
        );

        vm.prank(provider);
        claimPay.acceptSettlement(
            agreementId,
            1,
            ClaimPay.DisputeResolution.RefundClient
        );

        (, , ClaimPay.MilestoneStatus secondMilestoneStatus) = claimPay
            .getMilestone(agreementId, 1);

        (, , , ClaimPay.AgreementStatus finalAgreementStatus, ) = claimPay
            .getAgreement(agreementId);

        (bool proposalExistsAfter, address proposalAuthorAfter, ) = claimPay
            .getSettlementProposal(agreementId, 1);

        assertEq(
            uint256(secondMilestoneStatus),
            uint256(ClaimPay.MilestoneStatus.Refunded)
        );

        assertEq(
            uint256(finalAgreementStatus),
            uint256(ClaimPay.AgreementStatus.Completed)
        );

        assertEq(
            mockUSDC.balanceOf(client),
            clientBalanceAfterFunding + amounts[1]
        );

        assertEq(
            mockUSDC.balanceOf(provider),
            providerBalanceBefore + amounts[0]
        );

        assertEq(mockUSDC.balanceOf(address(claimPay)), 0);

        assertFalse(proposalExistsAfter);
        assertEq(proposalAuthorAfter, address(0));
    }
    function testRevertWhenAcceptingSettlementForPendingMilestone() public {
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Planification";

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 325 * 10 ** 6;

        vm.prank(client);
        uint256 agreementId = claimPay.createAgreement(
            provider,
            address(0),
            descriptions,
            amounts
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ClaimPay.InvalidMilestoneStatus.selector,
                agreementId,
                0,
                ClaimPay.MilestoneStatus.Pending
            )
        );

        vm.prank(provider);
        claimPay.acceptSettlement(
            agreementId,
            0,
            ClaimPay.DisputeResolution.PayProvider
        );

        (, , ClaimPay.MilestoneStatus milestoneStatus) = claimPay.getMilestone(
            agreementId,
            0
        );

        assertEq(
            uint256(milestoneStatus),
            uint256(ClaimPay.MilestoneStatus.Pending)
        );

        assertEq(mockUSDC.balanceOf(address(claimPay)), amounts[0]);
    }

    function testRevertWhenAcceptingSettlementForSubmittedMilestone() public {
    string[] memory descriptions = new string[](1);
    descriptions[0] = "Execution";

    uint256[] memory amounts = new uint256[](1);
    amounts[0] = 425 * 10 ** 6;

    vm.prank(client);
    uint256 agreementId = claimPay.createAgreement(
        provider,
        address(0),
        descriptions,
        amounts
    );

    vm.prank(provider);
    claimPay.submitMilestone(agreementId, 0);

    vm.expectRevert(
        abi.encodeWithSelector(
            ClaimPay.InvalidMilestoneStatus.selector,
            agreementId,
            0,
            ClaimPay.MilestoneStatus.Submitted
        )
    );

    vm.prank(client);
    claimPay.acceptSettlement(
        agreementId,
        0,
        ClaimPay.DisputeResolution.PayProvider
    );

    (, , ClaimPay.MilestoneStatus milestoneStatus) = claimPay.getMilestone(
        agreementId,
        0
    );

    assertEq(
        uint256(milestoneStatus),
        uint256(ClaimPay.MilestoneStatus.Submitted)
    );

    assertEq(
        mockUSDC.balanceOf(address(claimPay)),
        amounts[0]
    );

    assertEq(mockUSDC.balanceOf(provider), 0);
}
}
