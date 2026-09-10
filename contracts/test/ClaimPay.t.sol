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
}
