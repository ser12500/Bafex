// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";

/**
 * @title BAFEXStaking
 * @dev Контракт стейкинга токенов BAFEX с поддержкой различных типов блокировок.
 *
 * Особенности:
 * - Soft Lock: гибкий вывод с сохранением доходности при хранении >30 дней
 * - Hard Lock: фиксированные сроки (3/6/12 месяцев) с повышенной доходностью
 * - Автоматические выплаты из фонда развития и комиссионных сборов
 * - Защита от reentrancy атак и возможность паузы
 * - Детальное логирование всех операций
 */
contract BAFEXStaking is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    /// @dev Структура для хранения информации о стейкинге
    struct StakeInfo {
        uint256 amount; // Количество застейканных токенов
        uint256 startTime; // Время начала стейкинга
        uint256 lastClaimTime; // Время последнего клейма
        uint256 totalClaimed; // Общее количество заклеймленных токенов
        StakingType stakingType; // Тип стейкинга
        uint256 lockDuration; // Длительность блокировки (для Hard Lock)
        bool isActive; // Активен ли стейкинг
    }

    /// @dev Типы стейкинга
    enum StakingType {
        SOFT_LOCK, // Гибкий вывод
        HARD_LOCK_3M, // Жесткая блокировка 3 месяца
        HARD_LOCK_6M, // Жесткая блокировка 6 месяцев
        HARD_LOCK_12M // Жесткая блокировка 12 месяцев

    }

    /// @dev Структура для конфигурации APY
    struct APYConfig {
        uint256 softLockAPY; // APY для Soft Lock (1%)
        uint256 hardLock3MAPY; // APY для Hard Lock 3M (3%)
        uint256 hardLock6MAPY; // APY для Hard Lock 6M (4.5%)
        uint256 hardLock12MAPY; // APY для Hard Lock 12M (6%)
        uint256 bonusThresholdDays; // Пороговое количество дней для бонуса (30)
    }

    /// @dev События для логирования
    event StakeCreated(address indexed user, uint256 amount, StakingType stakingType, uint256 lockDuration);
    event StakeWithdrawn(address indexed user, uint256 amount, uint256 rewards);
    event RewardsClaimed(address indexed user, uint256 amount);
    event RewardsDistributed(uint256 totalAmount);
    event APYUpdated(StakingType stakingType, uint256 newAPY);
    event EmergencyWithdraw(address indexed user, uint256 amount);

    /// @dev Токен для стейкинга
    IERC20 public immutable token;

    /// @dev Хранилище информации о стейкинге пользователей
    mapping(address => StakeInfo) public userStakes;

    /// @dev Хранилище общей статистики
    mapping(StakingType => uint256) public totalStakedByType;

    /// @dev Конфигурация APY
    APYConfig public apyConfig;

    /// @dev Общее количество застейканных токенов
    uint256 public totalStaked;

    /// @dev Общее количество распределенных наград
    uint256 public totalRewardsDistributed;

    /// @dev Резерв наград
    uint256 public rewardsReserve;

    /// @dev Минимальная сумма для стейкинга
    uint256 public minStakeAmount;

    /// @dev Константы
    uint256 public constant SECONDS_IN_DAY = 86400; // 24 часа в секундах
    uint256 public constant SECONDS_IN_MONTH = 2592000; // 30 дней в секундах
    uint256 public constant SECONDS_IN_3_MONTHS = 7776000; // 90 дней в секундах
    uint256 public constant SECONDS_IN_6_MONTHS = 15552000; // 180 дней в секундах
    uint256 public constant SECONDS_IN_12_MONTHS = 31104000; // 365 дней в секундах
    uint256 public constant MAX_APY = 1000; // Максимальный APY (1000 = 100%)
    uint256 public constant PRECISION = 10000; // Точность для расчетов (10000 = 100%)

    /**
     * @dev Конструктор инициализирует контракт стейкинга.
     * @param token_ Адрес токена BAFEX для стейкинга.
     */
    constructor(address token_) Ownable(msg.sender) {
        require(token_ != address(0), "BAFEXStaking: token address cannot be zero");
        token = IERC20(token_);

        // Устанавливаем начальную конфигурацию APY
        apyConfig = APYConfig({
            softLockAPY: 100, // 1%
            hardLock3MAPY: 300, // 3%
            hardLock6MAPY: 450, // 4.5%
            hardLock12MAPY: 600, // 6%
            bonusThresholdDays: 30 // 30 дней
        });

        minStakeAmount = 1000 * 10 ** 18; // Минимум 1000 токенов
    }

    /**
     * @dev Создает новый стейкинг.
     * @param amount Количество токенов для стейкинга.
     * @param stakingType Тип стейкинга.
     */
    function stake(uint256 amount, StakingType stakingType) external nonReentrant whenNotPaused {
        require(amount >= minStakeAmount, "BAFEXStaking: amount below minimum");
        require(amount > 0, "BAFEXStaking: amount must be greater than 0");
        require(!userStakes[msg.sender].isActive, "BAFEXStaking: user already has active stake");
        require(token.balanceOf(msg.sender) >= amount, "BAFEXStaking: insufficient balance");

        uint256 lockDuration = _getLockDuration(stakingType);

        // Создаем новый стейкинг
        userStakes[msg.sender] = StakeInfo({
            amount: amount,
            startTime: block.timestamp,
            lastClaimTime: block.timestamp,
            totalClaimed: 0,
            stakingType: stakingType,
            lockDuration: lockDuration,
            isActive: true
        });

        // Обновляем статистику
        totalStaked += amount;
        totalStakedByType[stakingType] += amount;

        // Переводим токены в контракт
        token.safeTransferFrom(msg.sender, address(this), amount);

        emit StakeCreated(msg.sender, amount, stakingType, lockDuration);
    }

    /**
     * @dev Выводит стейкинг и все накопленные награды.
     */
    function unstake() external nonReentrant {
        StakeInfo storage userStake = userStakes[msg.sender];
        require(userStake.isActive, "BAFEXStaking: no active stake");

        uint256 rewards = calculateRewards(msg.sender);
        uint256 totalAmount = userStake.amount + rewards;

        // Проверяем, можно ли вывести (для Hard Lock)
        if (userStake.stakingType != StakingType.SOFT_LOCK) {
            require(
                block.timestamp >= userStake.startTime + userStake.lockDuration, "BAFEXStaking: stake is still locked"
            );
        }

        // Обновляем статистику
        totalStaked -= userStake.amount;
        totalStakedByType[userStake.stakingType] -= userStake.amount;
        totalRewardsDistributed += rewards;

        // Деактивируем стейкинг
        userStake.isActive = false;
        userStake.totalClaimed += rewards;

        // Переводим токены пользователю
        token.safeTransfer(msg.sender, totalAmount);

        emit StakeWithdrawn(msg.sender, userStake.amount, rewards);
    }

    /**
     * @dev Клеймит накопленные награды (только для Soft Lock).
     */
    function claimRewards() external nonReentrant {
        StakeInfo storage userStake = userStakes[msg.sender];
        require(userStake.isActive, "BAFEXStaking: no active stake");
        require(
            userStake.stakingType == StakingType.SOFT_LOCK, "BAFEXStaking: rewards can only be claimed for soft lock"
        );

        uint256 rewards = calculateRewards(msg.sender);
        require(rewards > 0, "BAFEXStaking: no rewards to claim");

        // Обновляем время последнего клейма
        userStake.lastClaimTime = block.timestamp;
        userStake.totalClaimed += rewards;
        totalRewardsDistributed += rewards;

        // Переводим награды пользователю
        token.safeTransfer(msg.sender, rewards);

        emit RewardsClaimed(msg.sender, rewards);
    }

    /**
     * @dev Экстренный вывод (только для Soft Lock, с потерей наград).
     */
    function emergencyWithdraw() external nonReentrant {
        StakeInfo storage userStake = userStakes[msg.sender];
        require(userStake.isActive, "BAFEXStaking: no active stake");
        require(userStake.stakingType == StakingType.SOFT_LOCK, "BAFEXStaking: emergency withdraw only for soft lock");

        uint256 amount = userStake.amount;

        // Обновляем статистику
        totalStaked -= amount;
        totalStakedByType[userStake.stakingType] -= amount;

        // Деактивируем стейкинг
        userStake.isActive = false;

        // Переводим только основную сумму (без наград)
        token.safeTransfer(msg.sender, amount);

        emit EmergencyWithdraw(msg.sender, amount);
    }

    /**
     * @dev Пополняет резерв наград (только владелец).
     * @param amount Количество токенов для добавления в резерв.
     */
    function addRewardsReserve(uint256 amount) external nonReentrant onlyOwner {
        require(amount > 0, "BAFEXStaking: amount must be greater than 0");
        rewardsReserve += amount;
        require(token.balanceOf(msg.sender) >= amount, "BAFEXStaking: insufficient balance");

        token.safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
     * @dev Распределяет награды между всеми стейкерами (только владелец).
     * @param amount Количество токенов для распределения.
     */
    function distributeRewards(uint256 amount) external onlyOwner {
        require(amount > 0, "BAFEXStaking: amount must be greater than 0");
        require(amount <= rewardsReserve, "BAFEXStaking: insufficient rewards reserve");
        require(totalStaked > 0, "BAFEXStaking: no staked tokens");

        rewardsReserve -= amount;
        totalRewardsDistributed += amount;

        emit RewardsDistributed(amount);
    }

    /**
     * @dev Обновляет APY для конкретного типа стейкинга (только владелец).
     * @param stakingType Тип стейкинга.
     * @param newAPY Новый APY (в базисных пунктах, 100 = 1%).
     */
    function updateAPY(StakingType stakingType, uint256 newAPY) external onlyOwner {
        require(newAPY <= MAX_APY, "BAFEXStaking: APY too high");

        if (stakingType == StakingType.SOFT_LOCK) {
            apyConfig.softLockAPY = newAPY;
        } else if (stakingType == StakingType.HARD_LOCK_3M) {
            apyConfig.hardLock3MAPY = newAPY;
        } else if (stakingType == StakingType.HARD_LOCK_6M) {
            apyConfig.hardLock6MAPY = newAPY;
        } else if (stakingType == StakingType.HARD_LOCK_12M) {
            apyConfig.hardLock12MAPY = newAPY;
        }

        emit APYUpdated(stakingType, newAPY);
    }

    /**
     * @dev Устанавливает минимальную сумму для стейкинга (только владелец).
     * @param amount Новая минимальная сумма.
     */
    function setMinStakeAmount(uint256 amount) external onlyOwner {
        require(amount > 0, "BAFEXStaking: amount must be greater than 0");
        minStakeAmount = amount;
    }

    /**
     * @dev Вычисляет накопленные награды пользователя.
     * @param user Адрес пользователя.
     * @return Количество накопленных наград.
     */
    function calculateRewards(address user) public view returns (uint256) {
        StakeInfo memory userStake = userStakes[user];
        if (!userStake.isActive) return 0;

        uint256 apy = _getAPY(userStake.stakingType);
        uint256 timeElapsed = block.timestamp - userStake.lastClaimTime;

        // Вычисляем награды: (amount * APY * timeElapsed) / (365 days * PRECISION)
        uint256 rewards = (userStake.amount * apy * timeElapsed) / (365 * SECONDS_IN_DAY * PRECISION);

        return rewards;
    }

    /**
     * @dev Вычисляет общие награды пользователя (включая уже заклеймленные).
     * @param user Адрес пользователя.
     * @return Общее количество наград.
     */
    function calculateTotalRewards(address user) public view returns (uint256) {
        StakeInfo memory userStake = userStakes[user];
        if (!userStake.isActive) return userStake.totalClaimed;

        uint256 currentRewards = calculateRewards(user);
        return userStake.totalClaimed + currentRewards;
    }

    /**
     * @dev Возвращает информацию о стейкинге пользователя.
     * @param user Адрес пользователя.
     * @return Структура с информацией о стейкинге.
     */
    function getUserStakeInfo(address user) external view returns (StakeInfo memory) {
        return userStakes[user];
    }

    /**
     * @dev Возвращает общую статистику стейкинга.
     * @return totalStaked_ Общее количество застейканных токенов.
     * @return totalRewardsDistributed_ Общее количество распределенных наград.
     * @return rewardsReserve_ Текущий резерв наград.
     */
    function getStakingStats()
        external
        view
        returns (uint256 totalStaked_, uint256 totalRewardsDistributed_, uint256 rewardsReserve_)
    {
        return (totalStaked, totalRewardsDistributed, rewardsReserve);
    }

    /**
     * @dev Возвращает конфигурацию APY.
     * @return Конфигурация APY.
     */
    function getAPYConfig() external view returns (APYConfig memory) {
        return apyConfig;
    }

    /**
     * @dev Возвращает APY для конкретного типа стейкинга.
     * @param stakingType Тип стейкинга.
     * @return APY в базисных пунктах.
     */
    function getAPY(StakingType stakingType) external view returns (uint256) {
        return _getAPY(stakingType);
    }

    /**
     * @dev Возвращает длительность блокировки для типа стейкинга.
     * @param stakingType Тип стейкинга.
     * @return Длительность блокировки в секундах.
     */
    function getLockDuration(StakingType stakingType) external pure returns (uint256) {
        return _getLockDuration(stakingType);
    }

    /**
     * @dev Паузит контракт (только владелец).
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

    /**
     * @dev Внутренняя функция для получения APY.
     * @param stakingType Тип стейкинга.
     * @return APY в базисных пунктах.
     */
    function _getAPY(StakingType stakingType) internal view returns (uint256) {
        if (stakingType == StakingType.SOFT_LOCK) {
            return apyConfig.softLockAPY;
        } else if (stakingType == StakingType.HARD_LOCK_3M) {
            return apyConfig.hardLock3MAPY;
        } else if (stakingType == StakingType.HARD_LOCK_6M) {
            return apyConfig.hardLock6MAPY;
        } else if (stakingType == StakingType.HARD_LOCK_12M) {
            return apyConfig.hardLock12MAPY;
        }
        return 0;
    }

    /**
     * @dev Внутренняя функция для получения длительности блокировки.
     * @param stakingType Тип стейкинга.
     * @return Длительность блокировки в секундах.
     */
    function _getLockDuration(StakingType stakingType) internal pure returns (uint256) {
        if (stakingType == StakingType.SOFT_LOCK) {
            return 0; // Без блокировки
        } else if (stakingType == StakingType.HARD_LOCK_3M) {
            return SECONDS_IN_3_MONTHS;
        } else if (stakingType == StakingType.HARD_LOCK_6M) {
            return SECONDS_IN_6_MONTHS;
        } else if (stakingType == StakingType.HARD_LOCK_12M) {
            return SECONDS_IN_12_MONTHS;
        }
        return 0;
    }
}
