// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "lib/forge-std/src/Test.sol";
import {BAFEXToken} from "../src/Token.sol";
import {BAFEXStaking} from "../src/BAFEXStaking.sol";

/**
 * @title BAFEXStakingTest
 * @dev Комплексные тесты для контракта стейкинга BAFEX.
 * Покрывает все типы стейкинга и edge cases.
 */
contract BAFEXStakingTest is Test {
    BAFEXToken public token;
    BAFEXStaking public staking;

    address public owner;
    address public user1;
    address public user2;
    address public user3;

    uint256 public constant STAKE_AMOUNT = 10000 * 10 ** 18;
    uint256 public constant REWARDS_AMOUNT = 100000 * 10 ** 18;

    event StakeCreated(
        address indexed user, uint256 amount, BAFEXStaking.StakingType stakingType, uint256 lockDuration
    );
    event StakeWithdrawn(address indexed user, uint256 amount, uint256 rewards);
    event RewardsClaimed(address indexed user, uint256 amount);

    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);
        user3 = address(0x3);

        token = new BAFEXToken();
        staking = new BAFEXStaking(address(token));

        // Переводим токены пользователям для стейкинга
        token.transfer(user1, 100000 * 10 ** 18);
        token.transfer(user2, 100000 * 10 ** 18);
        token.transfer(user3, 100000 * 10 ** 18);

        // Пополняем резерв наград
        token.transfer(address(staking), REWARDS_AMOUNT);
        // Добавляем резерв наград (требует approve)
        token.approve(address(staking), REWARDS_AMOUNT);
        staking.addRewardsReserve(REWARDS_AMOUNT);

        // Даем разрешения на стейкинг
        vm.prank(user1);
        token.approve(address(staking), type(uint256).max);
        vm.prank(user2);
        token.approve(address(staking), type(uint256).max);
        vm.prank(user3);
        token.approve(address(staking), type(uint256).max);
    }

    function testSoftLockStaking() public {
        vm.prank(user1);

        vm.expectEmit(true, true, false, true);
        emit StakeCreated(user1, STAKE_AMOUNT, BAFEXStaking.StakingType.SOFT_LOCK, 0);

        staking.stake(STAKE_AMOUNT, BAFEXStaking.StakingType.SOFT_LOCK);

        (
            uint256 amount,
            uint256 startTime,
            uint256 lastClaimTime,
            uint256 totalClaimed,
            BAFEXStaking.StakingType stakingType,
            uint256 lockDuration,
            bool isActive
        ) = staking.userStakes(user1);

        assertEq(amount, STAKE_AMOUNT);
        assertEq(startTime, block.timestamp);
        assertEq(lastClaimTime, block.timestamp);
        assertEq(totalClaimed, 0);
        assertEq(uint256(stakingType), uint256(BAFEXStaking.StakingType.SOFT_LOCK));
        assertEq(lockDuration, 0);
        assertTrue(isActive);

        assertEq(staking.totalStaked(), STAKE_AMOUNT);
        assertEq(staking.totalStakedByType(BAFEXStaking.StakingType.SOFT_LOCK), STAKE_AMOUNT);
    }

    function testHardLock3MStaking() public {
        vm.prank(user1);
        staking.stake(STAKE_AMOUNT, BAFEXStaking.StakingType.HARD_LOCK_3M);

        (,,,,, uint256 lockDuration,) = staking.userStakes(user1);
        assertEq(lockDuration, 7776000); // 90 дней в секундах

        assertEq(staking.getLockDuration(BAFEXStaking.StakingType.HARD_LOCK_3M), 7776000);
    }

    function testHardLock6MStaking() public {
        vm.prank(user1);
        staking.stake(STAKE_AMOUNT, BAFEXStaking.StakingType.HARD_LOCK_6M);

        (,,,,, uint256 lockDuration,) = staking.userStakes(user1);
        assertEq(lockDuration, 15552000); // 180 дней в секундах
    }

    function testHardLock12MStaking() public {
        vm.prank(user1);
        staking.stake(STAKE_AMOUNT, BAFEXStaking.StakingType.HARD_LOCK_12M);

        (,,,,, uint256 lockDuration,) = staking.userStakes(user1);
        assertEq(lockDuration, 31104000); // 365 дней в секундах
    }

    function testSoftLockUnstaking() public {
        vm.prank(user1);
        staking.stake(STAKE_AMOUNT, BAFEXStaking.StakingType.SOFT_LOCK);

        // Переходим на 30 дней вперед
        vm.warp(block.timestamp + 30 * 86400);

        uint256 initialBalance = token.balanceOf(user1);
        uint256 expectedRewards = staking.calculateRewards(user1);

        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit StakeWithdrawn(user1, STAKE_AMOUNT, expectedRewards);
        staking.unstake();

        assertEq(token.balanceOf(user1), initialBalance + STAKE_AMOUNT + expectedRewards);

        (,,,,,, bool isActive) = staking.userStakes(user1);
        assertFalse(isActive);

        assertEq(staking.totalStaked(), 0);
    }

    function testSoftLockClaimRewards() public {
        vm.prank(user1);
        staking.stake(STAKE_AMOUNT, BAFEXStaking.StakingType.SOFT_LOCK);

        // Переходим на 30 дней вперед
        vm.warp(block.timestamp + 30 * 86400);

        uint256 initialBalance = token.balanceOf(user1);
        uint256 expectedRewards = staking.calculateRewards(user1);

        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit RewardsClaimed(user1, expectedRewards);
        staking.claimRewards();

        assertEq(token.balanceOf(user1), initialBalance + expectedRewards);

        // Проверяем, что стейкинг все еще активен
        (,,,,,, bool isActive) = staking.userStakes(user1);
        assertTrue(isActive);
    }

    function testHardLockCannotUnstakeEarly() public {
        vm.prank(user1);
        staking.stake(STAKE_AMOUNT, BAFEXStaking.StakingType.HARD_LOCK_3M);

        // Переходим только на 30 дней (меньше чем 90 дней блокировки)
        vm.warp(block.timestamp + 30 * 86400);

        vm.prank(user1);
        vm.expectRevert("BAFEXStaking: stake is still locked");
        staking.unstake();
    }

    function testHardLockUnstakingAfterLock() public {
        vm.prank(user1);
        staking.stake(STAKE_AMOUNT, BAFEXStaking.StakingType.HARD_LOCK_3M);

        // Переходим на 95 дней (больше чем 90 дней блокировки)
        vm.warp(block.timestamp + 95 * 86400);

        uint256 initialBalance = token.balanceOf(user1);
        uint256 expectedRewards = staking.calculateRewards(user1);

        vm.prank(user1);
        staking.unstake();

        assertEq(token.balanceOf(user1), initialBalance + STAKE_AMOUNT + expectedRewards);

        (,,,,,, bool isActive) = staking.userStakes(user1);
        assertFalse(isActive);
    }

    function testHardLockCannotClaimRewards() public {
        vm.prank(user1);
        staking.stake(STAKE_AMOUNT, BAFEXStaking.StakingType.HARD_LOCK_3M);

        // Переходим на 30 дней вперед
        vm.warp(block.timestamp + 30 * 86400);

        vm.prank(user1);
        vm.expectRevert("BAFEXStaking: rewards can only be claimed for soft lock");
        staking.claimRewards();
    }

    function testEmergencyWithdraw() public {
        vm.prank(user1);
        staking.stake(STAKE_AMOUNT, BAFEXStaking.StakingType.SOFT_LOCK);

        uint256 initialBalance = token.balanceOf(user1);

        vm.prank(user1);
        staking.emergencyWithdraw();

        // Получаем только основную сумму, без наград
        assertEq(token.balanceOf(user1), initialBalance + STAKE_AMOUNT);

        (,,,,,, bool isActive) = staking.userStakes(user1);
        assertFalse(isActive);
    }

    function testEmergencyWithdrawOnlyForSoftLock() public {
        vm.prank(user1);
        staking.stake(STAKE_AMOUNT, BAFEXStaking.StakingType.HARD_LOCK_3M);

        vm.prank(user1);
        vm.expectRevert("BAFEXStaking: emergency withdraw only for soft lock");
        staking.emergencyWithdraw();
    }

    function testCalculateRewards() public {
        vm.prank(user1);
        staking.stake(STAKE_AMOUNT, BAFEXStaking.StakingType.SOFT_LOCK);

        // Переходим на 365 дней (1 год)
        vm.warp(block.timestamp + 365 * 86400);

        uint256 rewards = staking.calculateRewards(user1);
        uint256 expectedRewards = (STAKE_AMOUNT * 100 * 365 * 86400) / (365 * 86400 * 10000); // 1% APY

        assertEq(rewards, expectedRewards);
    }

    function testCalculateRewardsForHardLock() public {
        vm.prank(user1);
        staking.stake(STAKE_AMOUNT, BAFEXStaking.StakingType.HARD_LOCK_12M);

        // Переходим на 365 дней (1 год)
        vm.warp(block.timestamp + 365 * 86400);

        uint256 rewards = staking.calculateRewards(user1);
        uint256 expectedRewards = (STAKE_AMOUNT * 600 * 365 * 86400) / (365 * 86400 * 10000); // 6% APY

        assertEq(rewards, expectedRewards);
    }

    function testMultipleUsersStaking() public {
        vm.prank(user1);
        staking.stake(STAKE_AMOUNT, BAFEXStaking.StakingType.SOFT_LOCK);

        vm.prank(user2);
        staking.stake(STAKE_AMOUNT * 2, BAFEXStaking.StakingType.HARD_LOCK_6M);

        vm.prank(user3);
        staking.stake(STAKE_AMOUNT, BAFEXStaking.StakingType.HARD_LOCK_12M);

        assertEq(staking.totalStaked(), STAKE_AMOUNT * 4);
        assertEq(staking.totalStakedByType(BAFEXStaking.StakingType.SOFT_LOCK), STAKE_AMOUNT);
        assertEq(staking.totalStakedByType(BAFEXStaking.StakingType.HARD_LOCK_6M), STAKE_AMOUNT * 2);
        assertEq(staking.totalStakedByType(BAFEXStaking.StakingType.HARD_LOCK_12M), STAKE_AMOUNT);
    }

    function testUpdateAPY() public {
        uint256 newAPY = 200; // 2%

        staking.updateAPY(BAFEXStaking.StakingType.SOFT_LOCK, newAPY);

        assertEq(staking.getAPY(BAFEXStaking.StakingType.SOFT_LOCK), newAPY);
    }

    function testSetMinStakeAmount() public {
        uint256 newMinAmount = 5000 * 10 ** 18;

        staking.setMinStakeAmount(newMinAmount);

        assertEq(staking.minStakeAmount(), newMinAmount);
    }

    function testAddRewardsReserve() public {
        uint256 additionalRewards = 50000 * 10 ** 18;
        uint256 initialReserve = staking.rewardsReserve();

        // Нужно дать разрешение на перевод токенов
        token.approve(address(staking), additionalRewards);
        staking.addRewardsReserve(additionalRewards);

        assertEq(staking.rewardsReserve(), initialReserve + additionalRewards);
    }

    function testDistributeRewards() public {
        // Сначала создаем стейкинг
        vm.prank(user1);
        staking.stake(STAKE_AMOUNT, BAFEXStaking.StakingType.SOFT_LOCK);

        uint256 distributeAmount = 10000 * 10 ** 18;
        uint256 initialDistributed = staking.totalRewardsDistributed();

        staking.distributeRewards(distributeAmount);

        assertEq(staking.totalRewardsDistributed(), initialDistributed + distributeAmount);
        assertEq(staking.rewardsReserve(), REWARDS_AMOUNT - distributeAmount);
    }

    function testPauseAndUnpause() public {
        staking.pause();

        vm.prank(user1);
        vm.expectRevert();
        staking.stake(STAKE_AMOUNT, BAFEXStaking.StakingType.SOFT_LOCK);

        staking.unpause();

        vm.prank(user1);
        staking.stake(STAKE_AMOUNT, BAFEXStaking.StakingType.SOFT_LOCK);

        (,,,,,, bool isActive) = staking.userStakes(user1);
        assertTrue(isActive);
    }

    function testOnlyOwnerCanUpdateAPY() public {
        vm.prank(user1);
        vm.expectRevert();
        staking.updateAPY(BAFEXStaking.StakingType.SOFT_LOCK, 200);
    }

    function testOnlyOwnerCanSetMinStakeAmount() public {
        vm.prank(user1);
        vm.expectRevert();
        staking.setMinStakeAmount(5000 * 10 ** 18);
    }

    function testOnlyOwnerCanAddRewardsReserve() public {
        vm.prank(user1);
        vm.expectRevert();
        staking.addRewardsReserve(1000 * 10 ** 18);
    }

    function testOnlyOwnerCanDistributeRewards() public {
        vm.prank(user1);
        vm.expectRevert();
        staking.distributeRewards(1000 * 10 ** 18);
    }

    function testCannotStakeBelowMinimum() public {
        uint256 belowMinAmount = 500 * 10 ** 18; // Меньше минимума

        vm.prank(user1);
        vm.expectRevert("BAFEXStaking: amount below minimum");
        staking.stake(belowMinAmount, BAFEXStaking.StakingType.SOFT_LOCK);
    }

    function testCannotStakeZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert("BAFEXStaking: amount below minimum");
        staking.stake(0, BAFEXStaking.StakingType.SOFT_LOCK);
    }

    function testCannotStakeTwice() public {
        vm.prank(user1);
        staking.stake(STAKE_AMOUNT, BAFEXStaking.StakingType.SOFT_LOCK);

        vm.prank(user1);
        vm.expectRevert("BAFEXStaking: user already has active stake");
        staking.stake(STAKE_AMOUNT, BAFEXStaking.StakingType.SOFT_LOCK);
    }

    function testCannotStakeInsufficientBalance() public {
        address poorUser = address(0x999);
        token.transfer(poorUser, 100 * 10 ** 18); // Мало токенов

        vm.prank(poorUser);
        token.approve(address(staking), type(uint256).max);

        vm.prank(poorUser);
        vm.expectRevert("BAFEXStaking: insufficient balance");
        staking.stake(STAKE_AMOUNT, BAFEXStaking.StakingType.SOFT_LOCK);
    }

    function testCannotUnstakeWithoutActiveStake() public {
        vm.prank(user1);
        vm.expectRevert("BAFEXStaking: no active stake");
        staking.unstake();
    }

    function testCannotClaimRewardsWithoutActiveStake() public {
        vm.prank(user1);
        vm.expectRevert("BAFEXStaking: no active stake");
        staking.claimRewards();
    }

    function testCannotClaimZeroRewards() public {
        vm.prank(user1);
        staking.stake(STAKE_AMOUNT, BAFEXStaking.StakingType.SOFT_LOCK);

        // Не переходим во времени, наград еще нет
        vm.prank(user1);
        vm.expectRevert("BAFEXStaking: no rewards to claim");
        staking.claimRewards();
    }

    function testGetStakingStats() public {
        vm.prank(user1);
        staking.stake(STAKE_AMOUNT, BAFEXStaking.StakingType.SOFT_LOCK);

        (uint256 totalStaked_, uint256 totalRewardsDistributed_, uint256 rewardsReserve_) = staking.getStakingStats();

        assertEq(totalStaked_, STAKE_AMOUNT);
        assertEq(totalRewardsDistributed_, 0);
        assertEq(rewardsReserve_, REWARDS_AMOUNT);
    }

    function testGetAPYConfig() public {
        (
            uint256 softLockAPY,
            uint256 hardLock3MAPY,
            uint256 hardLock6MAPY,
            uint256 hardLock12MAPY,
            uint256 bonusThresholdDays
        ) = staking.apyConfig();

        assertEq(softLockAPY, 100); // 1%
        assertEq(hardLock3MAPY, 300); // 3%
        assertEq(hardLock6MAPY, 450); // 4.5%
        assertEq(hardLock12MAPY, 600); // 6%
        assertEq(bonusThresholdDays, 30);
    }

    function testGetUserStakeInfo() public {
        vm.prank(user1);
        staking.stake(STAKE_AMOUNT, BAFEXStaking.StakingType.SOFT_LOCK);

        (
            uint256 amount,
            uint256 startTime,
            uint256 lastClaimTime,
            uint256 totalClaimed,
            BAFEXStaking.StakingType stakingType,
            uint256 lockDuration,
            bool isActive
        ) = staking.userStakes(user1);

        assertEq(amount, STAKE_AMOUNT);
        assertEq(startTime, block.timestamp);
        assertEq(lastClaimTime, block.timestamp);
        assertEq(totalClaimed, 0);
        assertEq(uint256(stakingType), uint256(BAFEXStaking.StakingType.SOFT_LOCK));
        assertEq(lockDuration, 0);
        assertTrue(isActive);
    }
}
