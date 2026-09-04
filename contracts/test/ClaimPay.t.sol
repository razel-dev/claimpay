// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";
import {ClaimPay} from "../src/ClaimPay.sol";

contract ClaimPayTest is Test {
    ClaimPay internal claimPay;
    address internal client = makeAddr("client");
    address internal provider = makeAddr("provider");
    address internal arbiter = makeAddr("arbiter");
    event AgreementCreated(
        uint256 indexed agreementId,
        address indexed client,
        address indexed provider,
        address arbiter,
        uint256 milestoneCount
    );

    function setUp() public {
        claimPay = new ClaimPay();
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

        uint256 agreementId = claimPay.createAgreement(provider, arbiter, descriptions, amounts);

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
        assertEq(uint256(storedStatus), uint256(ClaimPay.AgreementStatus.Active));
        assertEq(milestoneCount, 1);

        (string memory storedDescription, uint256 storedAmount, ClaimPay.MilestoneStatus storedMilestoneStatus) =
            claimPay.getMilestone(agreementId, 0);

        assertEq(storedDescription, "Maquette");
        assertEq(storedAmount, 500);
        assertEq(uint256(storedMilestoneStatus), uint256(ClaimPay.MilestoneStatus.Pending));
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

        uint256 agreementId = claimPay.createAgreement(provider, address(0), descriptions, amounts);

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
}
