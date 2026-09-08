// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";

contract MockUSDCTest is Test {
    MockUSDC internal mockUSDC;

    function setUp() public {
        mockUSDC = new MockUSDC();
    }
    address internal recipient = makeAddr("recipient");

    function testTokenMetadata() public view {
        assertEq(mockUSDC.name(), "Mock USD Coin");
        assertEq(mockUSDC.symbol(), "mUSDC");
        assertEq(mockUSDC.decimals(), 6);
    }

    function testMint() public {
        uint256 amount = 500 * 10 ** 6;

        mockUSDC.mint(recipient, amount);

        assertEq(mockUSDC.balanceOf(recipient), amount);
        assertEq(mockUSDC.totalSupply(), amount);
    }
}
