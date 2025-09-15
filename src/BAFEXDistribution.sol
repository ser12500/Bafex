// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";

/**
 * @title BAFEXDistribution
 * @dev Контракт для управления распределением токенов BAFEX между различными категориями получателей.
 *
 * Особенности:
 * - Множественные категории распределения (команда, партнеры, маркетинг и т.д.)
 * - Контролируемое распределение с возможностью паузы
 * - Защита от reentrancy атак
 * - Детальное логирование всех операций
 * - Возможность отзыва неиспользованных токенов
 */
contract BAFEXDistribution is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    /// @dev Структура для хранения информации о категории распределения
    struct DistributionCategory {
        string name; // Название категории
        uint256 allocatedAmount; // Выделенное количество токенов
        uint256 distributedAmount; // Уже распределенное количество
        bool isActive; // Активна ли категория
        uint256 maxRecipients; // Максимальное количество получателей
        uint256 currentRecipients; // Текущее количество получателей
    }

    /// @dev Структура для получателя
    struct Recipient {
        address recipient; // Адрес получателя
        uint256 amount; // Количество токенов
        bool isDistributed; // Распределены ли токены
        uint256 distributionTime; // Время распределения
        string categoryName; // Название категории
    }

    /// @dev События для логирования
    event CategoryCreated(string indexed categoryName, uint256 allocatedAmount, uint256 maxRecipients);
    event TokensDistributed(string indexed categoryName, address indexed recipient, uint256 amount);
    event BatchDistributionCompleted(string indexed categoryName, uint256 totalAmount, uint256 recipientCount);
    event CategoryPaused(string indexed categoryName);
    event CategoryResumed(string indexed categoryName);
    event TokensWithdrawn(uint256 amount);
    event EmergencyWithdraw(address indexed token, uint256 amount);

    /// @dev Токен для распределения
    IERC20 public immutable token;

    /// @dev Хранилище категорий распределения
    mapping(string => DistributionCategory) public distributionCategories;

    /// @dev Хранилище получателей по категориям
    mapping(string => address[]) public categoryRecipients;

    /// @dev Хранилище детальной информации о получателях
    mapping(address => Recipient) public recipients;

    /// @dev Список всех категорий
    string[] public categoryNames;

    /// @dev Общее количество выделенных токенов
    uint256 public totalAllocated;

    /// @dev Общее количество распределенных токенов
    uint256 public totalDistributed;

    /// @dev Константы
    uint256 public constant MAX_CATEGORIES = 20; // Максимум категорий
    uint256 public constant MIN_ALLOCATION = 1000; // Минимальное выделение (в токенах)
    uint256 public constant MAX_BATCH_SIZE = 100; // Максимальный размер батча

    /**
     * @dev Конструктор инициализирует контракт распределения.
     * @param token_ Адрес токена BAFEX для распределения.
     */
    constructor(address token_) Ownable(msg.sender) {
        require(token_ != address(0), "BAFEXDistribution: token address cannot be zero");
        token = IERC20(token_);
    }

    /**
     * @dev Создает новую категорию распределения.
     * @param categoryName Название категории.
     * @param allocatedAmount Выделенное количество токенов.
     * @param maxRecipients Максимальное количество получателей.
     */
    function createCategory(string memory categoryName, uint256 allocatedAmount, uint256 maxRecipients)
        external
        onlyOwner
    {
        require(bytes(categoryName).length > 0, "BAFEXDistribution: category name cannot be empty");
        require(allocatedAmount >= MIN_ALLOCATION * 10 ** 18, "BAFEXDistribution: insufficient allocation");
        require(maxRecipients > 0, "BAFEXDistribution: max recipients must be greater than 0");
        require(!distributionCategories[categoryName].isActive, "BAFEXDistribution: category already exists");
        require(categoryNames.length < MAX_CATEGORIES, "BAFEXDistribution: too many categories");

        // Проверяем, что у нас достаточно токенов
        uint256 availableBalance = token.balanceOf(address(this));
        uint256 newTotalAllocated = totalAllocated + allocatedAmount;
        require(availableBalance >= newTotalAllocated, "BAFEXDistribution: insufficient token balance");

        distributionCategories[categoryName] = DistributionCategory({
            name: categoryName,
            allocatedAmount: allocatedAmount,
            distributedAmount: 0,
            isActive: true,
            maxRecipients: maxRecipients,
            currentRecipients: 0
        });

        categoryNames.push(categoryName);
        totalAllocated = newTotalAllocated;

        emit CategoryCreated(categoryName, allocatedAmount, maxRecipients);
    }

    /**
     * @dev Распределяет токены одному получателю.
     * @param categoryName Название категории.
     * @param recipient Адрес получателя.
     * @param amount Количество токенов для распределения.
     */
    function distributeToRecipient(string memory categoryName, address recipient, uint256 amount)
        external
        onlyOwner
        nonReentrant
        whenNotPaused
    {
        require(recipient != address(0), "BAFEXDistribution: recipient cannot be zero address");
        require(amount > 0, "BAFEXDistribution: amount must be greater than 0");

        DistributionCategory storage category = distributionCategories[categoryName];
        require(category.isActive, "BAFEXDistribution: category not active");
        require(
            category.distributedAmount + amount <= category.allocatedAmount,
            "BAFEXDistribution: insufficient category allocation"
        );
        require(category.currentRecipients < category.maxRecipients, "BAFEXDistribution: max recipients reached");

        // Проверяем, что получатель еще не получал токены в этой категории
        require(!recipients[recipient].isDistributed, "BAFEXDistribution: recipient already distributed");

        // Обновляем статистику
        category.distributedAmount += amount;
        category.currentRecipients += 1;
        totalDistributed += amount;

        // Записываем информацию о получателе
        recipients[recipient] = Recipient({
            recipient: recipient,
            amount: amount,
            isDistributed: true,
            distributionTime: block.timestamp,
            categoryName: categoryName
        });

        // Добавляем в список получателей категории
        categoryRecipients[categoryName].push(recipient);

        // Переводим токены
        token.safeTransfer(recipient, amount);

        emit TokensDistributed(categoryName, recipient, amount);
    }

    /**
     * @dev Распределяет токены нескольким получателям за один вызов.
     * @param categoryName Название категории.
     * @param recipients_ Массив адресов получателей.
     * @param amounts Массив количеств токенов для каждого получателя.
     */
    function distributeBatch(string memory categoryName, address[] memory recipients_, uint256[] memory amounts)
        external
        onlyOwner
        nonReentrant
        whenNotPaused
    {
        require(recipients_.length == amounts.length, "BAFEXDistribution: arrays length mismatch");
        require(recipients_.length <= MAX_BATCH_SIZE, "BAFEXDistribution: batch too large");
        require(recipients_.length > 0, "BAFEXDistribution: empty batch");

        DistributionCategory storage category = distributionCategories[categoryName];
        require(category.isActive, "BAFEXDistribution: category not active");

        uint256 totalBatchAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalBatchAmount += amounts[i];
        }

        require(
            category.distributedAmount + totalBatchAmount <= category.allocatedAmount,
            "BAFEXDistribution: insufficient category allocation"
        );
        require(
            category.currentRecipients + recipients_.length <= category.maxRecipients,
            "BAFEXDistribution: would exceed max recipients"
        );

        // Проверяем, что все получатели еще не получали токены
        for (uint256 i = 0; i < recipients_.length; i++) {
            require(recipients_[i] != address(0), "BAFEXDistribution: zero address in batch");
            require(!recipients[recipients_[i]].isDistributed, "BAFEXDistribution: recipient already distributed");
        }

        // Обновляем статистику
        category.distributedAmount += totalBatchAmount;
        category.currentRecipients += recipients_.length;
        totalDistributed += totalBatchAmount;

        // Распределяем токены
        // исправить переполнение !!!!!!!!!!
        for (uint256 i = 0; i < recipients_.length; i++) {
            // Записываем информацию о получателе
            recipients[recipients_[i]] = Recipient({
                recipient: recipients_[i],
                amount: amounts[i],
                isDistributed: true,
                distributionTime: block.timestamp,
                categoryName: categoryName
            });

            // Добавляем в список получателей категории
            categoryRecipients[categoryName].push(recipients_[i]);

            // Переводим токены
            token.safeTransfer(recipients_[i], amounts[i]);

            emit TokensDistributed(categoryName, recipients_[i], amounts[i]);
        }

        emit BatchDistributionCompleted(categoryName, totalBatchAmount, recipients_.length);
    }

    /**
     * @dev Приостанавливает категорию распределения.
     * @param categoryName Название категории.
     */
    function pauseCategory(string memory categoryName) external onlyOwner {
        DistributionCategory storage category = distributionCategories[categoryName];
        require(category.isActive, "BAFEXDistribution: category not found or already paused");

        category.isActive = false;
        emit CategoryPaused(categoryName);
    }

    /**
     * @dev Возобновляет категорию распределения.
     * @param categoryName Название категории.
     */
    function resumeCategory(string memory categoryName) external onlyOwner {
        DistributionCategory storage category = distributionCategories[categoryName];
        require(
            !category.isActive && bytes(category.name).length > 0,
            "BAFEXDistribution: category not found or already active"
        );

        category.isActive = true;
        emit CategoryResumed(categoryName);
    }

    /**
     * @dev Извлекает неиспользованные токены (только владелец).
     * @param amount Количество токенов для извлечения.
     */
    function withdrawUnusedTokens(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "BAFEXDistribution: amount must be greater than 0");

        uint256 availableForWithdrawal = token.balanceOf(address(this)) - (totalAllocated - totalDistributed);
        require(availableForWithdrawal >= amount, "BAFEXDistribution: insufficient unused tokens");

        token.safeTransfer(owner(), amount);
        emit TokensWithdrawn(amount);
    }

    /**
     * @dev Экстренное извлечение всех токенов (только владелец).
     */
    function emergencyWithdraw() external onlyOwner {
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, "BAFEXDistribution: no tokens to withdraw");

        token.safeTransfer(owner(), balance);
        emit EmergencyWithdraw(address(token), balance);
    }

    /**
     * @dev Возвращает информацию о категории.
     * @param categoryName Название категории.
     * @return category Структура с информацией о категории.
     */
    function getCategoryInfo(string memory categoryName) external view returns (DistributionCategory memory) {
        return distributionCategories[categoryName];
    }

    /**
     * @dev Возвращает список получателей категории.
     * @param categoryName Название категории.
     * @return Массив адресов получателей.
     */
    function getCategoryRecipients(string memory categoryName) external view returns (address[] memory) {
        return categoryRecipients[categoryName];
    }

    /**
     * @dev Возвращает количество получателей в категории.
     * @param categoryName Название категории.
     * @return Количество получателей.
     */
    function getCategoryRecipientsCount(string memory categoryName) external view returns (uint256) {
        return categoryRecipients[categoryName].length;
    }

    /**
     * @dev Возвращает общее количество неиспользованных токенов.
     * @return Количество неиспользованных токенов.
     */
    function getUnusedTokens() external view returns (uint256) {
        return token.balanceOf(address(this)) - (totalAllocated - totalDistributed);
    }

    /**
     * @dev Возвращает количество активных категорий.
     * @return Количество активных категорий.
     */
    function getActiveCategoriesCount() external view returns (uint256) {
        uint256 count = 0;

        for (uint256 i = 0; i < categoryNames.length; i++) {
            if (distributionCategories[categoryNames[i]].isActive) {
                count++;
            }
        }
        return count;
    }

    /**
     * @dev Возвращает все названия категорий.
     * @return Массив названий категорий.
     */
    function getAllCategoryNames() external view returns (string[] memory) {
        return categoryNames;
    }

    /**
     * @dev Паузит весь контракт (только владелец).
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Снимает паузу с контракта (только владелец).
     */
    function unpause() external onlyOwner {
        _unpause();
    }
}
