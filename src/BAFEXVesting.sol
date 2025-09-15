// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

/**
 * @title BAFEXVesting
 * @dev Контракт для вестинга токенов BAFEX с поддержкой различных типов вестинга.
 * Поддерживает линейный и клифф вестинг с возможностью создания множественных планов.
 *
 */
contract BAFEXVesting is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @dev Структура для хранения информации о вестинге
    struct VestingSchedule {
        bool initialized; // Инициализирован ли план
        bool revoked; // Отозван ли план
        address beneficiary; // Бенефициар вестинга
        uint256 cliff; // Период клиффа (в секундах)
        uint256 start; // Время начала вестинга
        uint256 duration; // Общая продолжительность вестинга
        uint256 slicePeriodSeconds; // Период начисления (в секундах)
        uint256 amountTotal; // Общее количество токенов
        uint256 released; // Уже выпущенные токенов
        VestingType vestingType; // Тип вестинга
    }

    /// @dev Типы вестинга
    enum VestingType {
        LINEAR, // Линейный вестинг
        CLIFF // Клифф вестинг

    }

    /// @dev События для логирования
    event VestingScheduleCreated(bytes32 vestingScheduleId, address beneficiary, uint256 amount);
    event TokensReleased(bytes32 vestingScheduleId, uint256 amount);
    event VestingScheduleRevoked(bytes32 vestingScheduleId);
    event TokensWithdrawn(address token, uint256 amount);

    /// @dev Хранилище планов вестинга
    mapping(bytes32 => VestingSchedule) public vestingSchedules;

    /// @dev Хранилище планов для каждого бенефициара
    mapping(address => bytes32[]) public vestingSchedulesIdsByBeneficiary;

    /// @dev Общее количество планов
    uint256 public vestingSchedulesTotalAmount;

    /// @dev Токен для вестинга
    IERC20 public immutable token;

    /// @dev Константы
    uint256 public constant MAX_VESTING_DURATION = 365 days * 10; // 10 лет максимум
    uint256 public constant MIN_VESTING_DURATION = 1 days; // 1 день минимум

    /**
     * @dev Конструктор инициализирует контракт вестинга.
     * @param token_ Адрес токена BAFEX для вестинга.
     */
    constructor(address token_) Ownable(msg.sender) {
        require(token_ != address(0), "BAFEXVesting: token address cannot be zero");
        token = IERC20(token_);
    }

    /**
     * @dev Создает новый план вестинга.
     * @param beneficiary_ Адрес бенефициара.
     * @param start_ Время начала вестинга.
     * @param cliff_ Период клиффа (для CLIFF типа).
     * @param duration_ Общая продолжительность вестинга.
     * @param slicePeriodSeconds_ Период начисления токенов.
     * @param amount_ Количество токенов для вестинга.
     * @param vestingType_ Тип вестинга (LINEAR или CLIFF).
     * @return vestingScheduleId Уникальный ID плана вестинга.
     */
    function createVestingSchedule(
        address beneficiary_,
        uint256 start_,
        uint256 cliff_,
        uint256 duration_,
        uint256 slicePeriodSeconds_,
        uint256 amount_,
        VestingType vestingType_
    ) external onlyOwner returns (bytes32 vestingScheduleId) {
        require(beneficiary_ != address(0), "BAFEXVesting: beneficiary cannot be zero address");
        require(amount_ > 0, "BAFEXVesting: amount must be greater than 0");
        require(
            duration_ >= MIN_VESTING_DURATION && duration_ <= MAX_VESTING_DURATION, "BAFEXVesting: invalid duration"
        );
        require(slicePeriodSeconds_ >= 1, "BAFEXVesting: slice period must be at least 1 second");

        if (vestingType_ == VestingType.CLIFF) {
            require(cliff_ >= 0 && cliff_ <= duration_, "BAFEXVesting: invalid cliff period");
        }

        vestingScheduleId = computeVestingScheduleIdForAddressAndIndex(
            beneficiary_, vestingSchedulesIdsByBeneficiary[beneficiary_].length
        );

        vestingSchedules[vestingScheduleId] = VestingSchedule(
            true, false, beneficiary_, cliff_, start_, duration_, slicePeriodSeconds_, amount_, 0, vestingType_
        );

        vestingSchedulesTotalAmount += amount_;
        vestingSchedulesIdsByBeneficiary[beneficiary_].push(vestingScheduleId);

        emit VestingScheduleCreated(vestingScheduleId, beneficiary_, amount_);
    }

    /**
     * @dev Выпускает доступные токены для конкретного плана вестинга.
     * @param vestingScheduleId ID плана вестинга.
     * @param amount Количество токенов для выпуска.
     */
    function release(bytes32 vestingScheduleId, uint256 amount) external nonReentrant {
        VestingSchedule storage vestingSchedule = vestingSchedules[vestingScheduleId];
        require(vestingSchedule.initialized, "BAFEXVesting: vesting schedule not initialized");
        require(!vestingSchedule.revoked, "BAFEXVesting: vesting schedule revoked");
        require(
            msg.sender == vestingSchedule.beneficiary || msg.sender == owner(),
            "BAFEXVesting: only beneficiary or owner can release"
        );

        uint256 vestedAmount = _computeReleasableAmount(vestingSchedule);
        require(vestedAmount >= amount, "BAFEXVesting: not enough vested tokens");
        require(amount > 0, "BAFEXVesting: amount must be greater than 0");

        vestingSchedule.released += amount;
        vestingSchedulesTotalAmount -= amount;

        token.safeTransfer(vestingSchedule.beneficiary, amount);

        emit TokensReleased(vestingScheduleId, amount);
    }

    /**
     * @dev Выпускает все доступные токены для конкретного плана вестинга.
     * @param vestingScheduleId ID плана вестинга.
     */
    function releaseAll(bytes32 vestingScheduleId) external nonReentrant {
        VestingSchedule storage vestingSchedule = vestingSchedules[vestingScheduleId];
        require(vestingSchedule.initialized, "BAFEXVesting: vesting schedule not initialized");
        require(!vestingSchedule.revoked, "BAFEXVesting: vesting schedule revoked");
        require(
            msg.sender == vestingSchedule.beneficiary || msg.sender == owner(),
            "BAFEXVesting: only beneficiary or owner can release"
        );

        uint256 vestedAmount = _computeReleasableAmount(vestingSchedule);
        require(vestedAmount > 0, "BAFEXVesting: no tokens to release");

        vestingSchedule.released += vestedAmount;
        vestingSchedulesTotalAmount -= vestedAmount;

        token.safeTransfer(vestingSchedule.beneficiary, vestedAmount);

        emit TokensReleased(vestingScheduleId, vestedAmount);
    }

    /**
     * @dev Отзывает план вестинга (только владелец).
     * @param vestingScheduleId ID плана вестинга.
     */
    function revoke(bytes32 vestingScheduleId) external onlyOwner {
        VestingSchedule storage vestingSchedule = vestingSchedules[vestingScheduleId];
        require(vestingSchedule.initialized, "BAFEXVesting: vesting schedule not initialized");
        require(!vestingSchedule.revoked, "BAFEXVesting: vesting schedule already revoked");

        uint256 vestedAmount = _computeReleasableAmount(vestingSchedule);
        if (vestedAmount > 0) {
            vestingSchedule.released += vestedAmount;
            vestingSchedulesTotalAmount -= vestedAmount;
            token.safeTransfer(vestingSchedule.beneficiary, vestedAmount);
            emit TokensReleased(vestingScheduleId, vestedAmount);
        }

        uint256 unreleased = vestingSchedule.amountTotal - vestingSchedule.released;
        vestingSchedulesTotalAmount -= unreleased;
        vestingSchedule.revoked = true;

        emit VestingScheduleRevoked(vestingScheduleId);
    }

    /**
     * @dev Извлекает нераспределенные токены (только владелец).
     * @param amount Количество токенов для извлечения.
     */
    function withdraw(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "BAFEXVesting: amount must be greater than 0");
        uint256 balance = token.balanceOf(address(this));
        require(balance >= amount, "BAFEXVesting: insufficient balance");

        token.safeTransfer(owner(), amount);
        emit TokensWithdrawn(address(token), amount);
    }

    /**
     * @dev Вычисляет количество доступных для выпуска токенов.
     * @param vestingScheduleId ID плана вестинга.
     * @return Количество доступных токенов.
     */
    function computeReleasableAmount(bytes32 vestingScheduleId) external view returns (uint256) {
        VestingSchedule storage vestingSchedule = vestingSchedules[vestingScheduleId];
        require(vestingSchedule.initialized, "BAFEXVesting: vesting schedule not initialized");
        return _computeReleasableAmount(vestingSchedule);
    }

    /**
     * @dev Вычисляет общее количество вестинговых токенов для бенефициара.
     * @param beneficiary Адрес бенефициара.
     * @return Общее количество токенов.
     */
    function computeVestedAmount(address beneficiary) external view returns (uint256) {
        uint256 totalVestedAmount = 0;
        bytes32[] memory vestingScheduleIds = vestingSchedulesIdsByBeneficiary[beneficiary];

        for (uint256 i = 0; i < vestingScheduleIds.length; i++) {
            VestingSchedule storage vestingSchedule = vestingSchedules[vestingScheduleIds[i]];
            if (vestingSchedule.initialized && !vestingSchedule.revoked) {
                totalVestedAmount += _computeVestedAmount(vestingSchedule);
            }
        }

        return totalVestedAmount;
    }

    /**
     * @dev Возвращает количество планов вестинга для бенефициара.
     * @param beneficiary Адрес бенефициара.
     * @return Количество планов.
     */
    function getVestingSchedulesCountByBeneficiary(address beneficiary) external view returns (uint256) {
        return vestingSchedulesIdsByBeneficiary[beneficiary].length;
    }

    /**
     * @dev Возвращает ID плана вестинга по индексу для бенефициара.
     * @param beneficiary Адрес бенефициара.
     * @param index Индекс плана.
     * @return ID плана вестинга.
     */
    function getVestingScheduleAtIndex(address beneficiary, uint256 index) external view returns (bytes32) {
        require(index < vestingSchedulesIdsByBeneficiary[beneficiary].length, "BAFEXVesting: index out of bounds");
        return vestingSchedulesIdsByBeneficiary[beneficiary][index];
    }

    /**
     * @dev Вычисляет уникальный ID плана вестинга.
     * @param beneficiary Адрес бенефициара.
     * @param index Индекс плана.
     * @return Уникальный ID плана.
     */
    function computeVestingScheduleIdForAddressAndIndex(address beneficiary, uint256 index)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(beneficiary, index));
    }

    /**
     * @dev Внутренняя функция для вычисления доступных токенов.
     * @param vestingSchedule План вестинга.
     * @return Количество доступных токенов.
     */
    function _computeReleasableAmount(VestingSchedule memory vestingSchedule) internal view returns (uint256) {
        uint256 vestedAmount = _computeVestedAmount(vestingSchedule);
        return vestedAmount - vestingSchedule.released;
    }

    /**
     * @dev Внутренняя функция для вычисления вестинговых токенов.
     * @param vestingSchedule План вестинга.
     * @return Количество вестинговых токенов.
     */
    function _computeVestedAmount(VestingSchedule memory vestingSchedule) internal view returns (uint256) {
        uint256 currentTime = block.timestamp;

        if (currentTime < vestingSchedule.start) {
            return 0;
        }

        uint256 timeFromStart = currentTime - vestingSchedule.start;

        if (vestingSchedule.vestingType == VestingType.CLIFF) {
            if (timeFromStart < vestingSchedule.cliff) {
                return 0;
            }
            timeFromStart -= vestingSchedule.cliff;
        }

        uint256 totalVestingDuration = vestingSchedule.duration;
        if (vestingSchedule.vestingType == VestingType.CLIFF) {
            totalVestingDuration -= vestingSchedule.cliff;
        }

        if (timeFromStart >= totalVestingDuration) {
            return vestingSchedule.amountTotal;
        }

        return (vestingSchedule.amountTotal * timeFromStart) / totalVestingDuration;
    }
}
