// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {BAFEXPaymentGateway} from "../src/BAFEXPaymentGateway.sol";
import {BAFEXToken} from "../src/Token.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract MockUSDT is BAFEXToken {
    constructor() BAFEXToken() {}
}

contract MockUSDC is BAFEXToken {
    constructor() BAFEXToken() {}
}

contract BAFEXPaymentGatewayTest is Test {
    BAFEXToken private bafex;
    MockUSDT private usdt;
    MockUSDC private usdc;
    BAFEXPaymentGateway private gateway;
    address private user = address(0x1);
    address private owner = address(this);

    function setUp() public {
        bafex = new BAFEXToken();
        usdt = new MockUSDT();
        usdc = new MockUSDC();
        gateway = new BAFEXPaymentGateway();
        // Пополняем юзеру 10к каждого токена
        bafex.transfer(user, 10_000 ether);
        usdt.transfer(user, 10_000 ether);
        usdc.transfer(user, 10_000 ether);
        // Добавляем whitelist
        gateway.allowToken(address(bafex), true);
        gateway.allowToken(address(usdt), true);
        gateway.allowToken(address(usdc), true);
    }

    function testPayInBafex() public {
        uint256 orderId = 1;
        vm.prank(user);
        bafex.approve(address(gateway), 1_000 ether);
        vm.prank(user);
        gateway.payForProduct(orderId, address(bafex), 1_000 ether);
        assertEq(gateway.totalReceived(address(bafex)), 1_000 ether);
        (address payer, uint256 amount, address token, uint256 ts) = gateway.orderPayments(orderId);
        assertEq(payer, user);
        assertEq(amount, 1_000 ether);
        assertEq(token, address(bafex));
        assertGt(ts, 0);
    }

    function testPayInNotWhitelistedToken() public {
        BAFEXToken punk = new BAFEXToken();
        punk.transfer(user, 500 ether);
        vm.prank(user);
        punk.approve(address(gateway), 500 ether);
        vm.prank(user);
        vm.expectRevert("PG: token not allowed");
        gateway.payForProduct(2, address(punk), 500 ether);
    }

    function testCannotDoublePay() public {
        uint256 orderId = 7;
        vm.prank(user);
        bafex.approve(address(gateway), 100 ether);
        vm.prank(user);
        gateway.payForProduct(orderId, address(bafex), 100 ether);
        vm.prank(user);
        bafex.approve(address(gateway), 100 ether);
        vm.prank(user);
        vm.expectRevert("PG: order already paid");
        gateway.payForProduct(orderId, address(bafex), 100 ether);
    }

    function testWithdrawByOwner() public {
        uint256 orderId = 13;
        vm.prank(user);
        bafex.approve(address(gateway), 400 ether);
        vm.prank(user);
        gateway.payForProduct(orderId, address(bafex), 400 ether);
        uint256 before = bafex.balanceOf(owner);
        gateway.withdraw(address(bafex), owner, 400 ether);
        assertEq(bafex.balanceOf(owner), before + 400 ether);
    }

    function testAllowToken() public {
        assertTrue(gateway.allowedTokens(address(bafex)));
        gateway.allowToken(address(usdc), false);
        assertFalse(gateway.allowedTokens(address(usdc)));
    }

    function testZeroAmount() public {
        vm.prank(user);
        bafex.approve(address(gateway), 0);
        vm.prank(user);
        vm.expectRevert("PG: zero amount");
        gateway.payForProduct(11, address(bafex), 0);
    }

    function testWithdrawFailZeroAddress() public {
        gateway.allowToken(address(bafex), true);
        vm.expectRevert("PG: zero address");
        gateway.withdraw(address(bafex), address(0), 100 ether);
    }

    function testWithdrawFailNoFunds() public {
        gateway.allowToken(address(bafex), true);
        vm.expectRevert("PG: insufficient balance");
        gateway.withdraw(address(bafex), owner, 100 ether);
    }
}
