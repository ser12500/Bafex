// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

/**
 * @title BAFEXPaymentGateway
 * @dev Контракт для приема платежей за товары в USDT, USDC и BAFEX или других whitelisted токенах.
 * Поддерживает безопасные ERC20 платежи, регистрацию/отвязку обработчиков токенов и аудит всех оплат.
 */
contract BAFEXPaymentGateway is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @dev Событие успешной оплаты товара
    event ProductPaid(
        address indexed payer, uint256 indexed orderId, address indexed token, uint256 amount, uint256 timestamp
    );
    event TokenAllowed(address indexed token, bool allowed);
    event Withdraw(address indexed token, address indexed to, uint256 amount);

    /// @dev Разрешённые для оплаты токены (whitelist)
    mapping(address => bool) public allowedTokens;

    /// @dev Поступления по каждому токену
    mapping(address => uint256) public totalReceived;

    /// @dev Учет оплат по заказу
    struct PaymentInfo {
        address payer;
        uint256 amount;
        address token;
        uint256 timestamp;
    }

    mapping(uint256 => PaymentInfo) public orderPayments;

    /**
     * @dev Добавляет или удаляет токен из whitelist (только владелец).
     * @param token Адрес токена ERC20
     * @param allowed true для разрешения, false для удаления
     */
    function allowToken(address token, bool allowed) external onlyOwner {
        require(token != address(0), "PG: zero token");
        allowedTokens[token] = allowed;
        emit TokenAllowed(token, allowed);
    }

    /**
     * @dev Оплатить товар любым whitelisted ERC20 токеном
     * @param orderId ID заказа или товара
     * @param token Адрес токена для оплаты
     * @param amount Сумма токенов для оплаты
     */
    function payForProduct(uint256 orderId, address token, uint256 amount) external nonReentrant {
        require(allowedTokens[token], "PG: token not allowed");
        require(amount > 0, "PG: zero amount");
        require(orderPayments[orderId].amount == 0, "PG: order already paid");

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        totalReceived[token] += amount;
        orderPayments[orderId] =
            PaymentInfo({payer: msg.sender, amount: amount, token: token, timestamp: block.timestamp});
        emit ProductPaid(msg.sender, orderId, token, amount, block.timestamp);
    }

    /**
     * @dev Безопасно вывести собранные токены (только владелец).
     * @param token Адрес токена.
     * @param to Адрес получателя.
     * @param amount Сумма для вывода.
     */
    function withdraw(address token, address to, uint256 amount) external onlyOwner {
        require(amount > 0, "PG: zero amount");
        require(to != address(0), "PG: zero address");
        require(IERC20(token).balanceOf(address(this)) >= amount, "PG: insufficient balance");
        IERC20(token).safeTransfer(to, amount);
        emit Withdraw(token, to, amount);
    }

    /**
     * @dev Возвращает данные об оплате заказа.
     * @param orderId ID заказа или продукта.
     */
    function getPaymentInfo(uint256 orderId) external view returns (PaymentInfo memory) {
        return orderPayments[orderId];
    }
}
