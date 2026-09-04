// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";
import {ClaimPay} from "../src/ClaimPay.sol";

contract ClaimPayTest is Test {
    ClaimPay internal claimPay;

    function setUp() public {
        claimPay = new ClaimPay();
    }

    function testInitialAgreementCountIsZero() public view {
        assertEq(claimPay.agreementCount(), 0);
    }
}

