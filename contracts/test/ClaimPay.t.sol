// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";
import {ClaimPay} from "../src/ClaimPay.sol";

contract ClaimPayTest is Test {
    ClaimPay internal claimPay;
    address internal client = makeAddr("client");
    address internal provider = makeAddr("provider");
    address internal arbiter = makeAddr("arbiter");

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
    }
}
