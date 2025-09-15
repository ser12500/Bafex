// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "lib/forge-std/src/Test.sol";
import "../src/Token.sol";

contract BAFEXTokenTest is Test {
    BAFEXToken token;
    address owner = address(this);

    function setUp() public {
        token = new BAFEXToken();
    }

    function testInitialSupply() public {
        assertEq(token.totalSupply(), 10_000_000_000 * 10 ** 18);
        assertEq(token.balanceOf(owner), 10_000_000_000 * 10 ** 18);
    }

    function testTransfer() public {
        address recipient = address(0x123);
        token.transfer(recipient, 1000 * 10 ** 18);
        assertEq(token.balanceOf(recipient), 1000 * 10 ** 18);
    }

    function testDecimals() public {
        assertEq(token.decimals(), 18);
    }

    function testBurn() public {
        uint256 burnAmount = 1000 * 10 ** 18;
        uint256 initialBalance = token.balanceOf(owner);
        uint256 initialSupply = token.totalSupply();

        token.burn(burnAmount);

        assertEq(token.balanceOf(owner), initialBalance - burnAmount);
        assertEq(token.totalSupply(), initialSupply - burnAmount);
        assertEq(token.totalBurned(), burnAmount);
    }

    function testBurnFrom() public {
        address user = address(0x123);
        uint256 transferAmount = 10000 * 10 ** 18;
        uint256 burnAmount = 1000 * 10 ** 18;

        // Переводим токены пользователю
        token.transfer(user, transferAmount);

        // Даем разрешение на сжигание
        vm.prank(user);
        token.approve(owner, burnAmount);

        // Сжигаем токены от имени пользователя
        token.burnFrom(user, burnAmount);

        assertEq(token.balanceOf(user), transferAmount - burnAmount);
        assertEq(token.totalBurned(), burnAmount);
    }

    function testBurnFromOwner() public {
        uint256 burnAmount = 1000 * 10 ** 18;
        uint256 initialBalance = token.balanceOf(owner);
        uint256 initialSupply = token.totalSupply();

        token.burnFromOwner(burnAmount);

        assertEq(token.balanceOf(owner), initialBalance - burnAmount);
        assertEq(token.totalSupply(), initialSupply - burnAmount);
        assertEq(token.totalBurned(), burnAmount);
    }

    function testBurnAllFromOwner() public {
        uint256 initialBalance = token.balanceOf(owner);
        uint256 initialSupply = token.totalSupply();

        token.burnAllFromOwner();

        assertEq(token.balanceOf(owner), 0);
        assertEq(token.totalSupply(), 0);
        assertEq(token.totalBurned(), initialSupply);
    }

    function testBurnFromOwnerOnlyOwner() public {
        address user = address(0x123);

        vm.prank(user);
        vm.expectRevert();
        token.burnFromOwner(1000 * 10 ** 18);
    }

    function testBurnAllFromOwnerOnlyOwner() public {
        address user = address(0x123);

        vm.prank(user);
        vm.expectRevert();
        token.burnAllFromOwner();
    }

    function testBurnFromOwnerInsufficientBalance() public {
        uint256 burnAmount = token.balanceOf(owner) + 1;

        vm.expectRevert("BAFEX: insufficient balance");
        token.burnFromOwner(burnAmount);
    }

    function testBurnFromOwnerZeroAmount() public {
        vm.expectRevert("BAFEX: amount must be greater than 0");
        token.burnFromOwner(0);
    }

    function testTotalBurned() public {
        assertEq(token.totalBurned(), 0);

        token.burn(1000 * 10 ** 18);
        assertEq(token.totalBurned(), 1000 * 10 ** 18);

        token.burn(500 * 10 ** 18);
        assertEq(token.totalBurned(), 1500 * 10 ** 18);
    }
}
