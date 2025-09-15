// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "lib/forge-std/src/Test.sol";
import {BAFEXToken} from "../src/Token.sol";
import {BAFEXVesting} from "../src/BAFEXVesting.sol";

/**
 * @title BAFEXVestingTest
 * @dev Комплексные тесты для контракта вестинга BAFEX.
 * Покрывает все основные сценарии использования и edge cases.
 */
contract BAFEXVestingTest is Test {
    BAFEXToken public token;
    BAFEXVesting public vesting;

    address public owner;
    address public beneficiary1;
    address public beneficiary2;

    uint256 public constant VESTING_AMOUNT = 100_000 * 10 ** 18;
    uint256 public constant VESTING_DURATION = 365 days;
    uint256 public constant CLIFF_DURATION = 90 days;

    event VestingScheduleCreated(bytes32 vestingScheduleId, address beneficiary, uint256 amount);
    event TokensReleased(bytes32 vestingScheduleId, uint256 amount);
    event VestingScheduleRevoked(bytes32 vestingScheduleId);

    function setUp() public {
        owner = address(this);
        beneficiary1 = address(0x1);
        beneficiary2 = address(0x2);

        token = new BAFEXToken();
        vesting = new BAFEXVesting(address(token));

        // Переводим токены в контракт вестинга
        token.transfer(address(vesting), 10_000_000 * 10 ** 18);
    }

    function testCreateLinearVestingSchedule() public {
        uint256 startTime = block.timestamp;

        bytes32 vestingId = vesting.createVestingSchedule(
            beneficiary1,
            startTime,
            0, // no cliff for linear vesting
            VESTING_DURATION,
            1 days,
            VESTING_AMOUNT,
            BAFEXVesting.VestingType.LINEAR
        );

        assertTrue(vestingId != bytes32(0));
        assertEq(vesting.getVestingSchedulesCountByBeneficiary(beneficiary1), 1);

        // Проверяем, что план вестинга был создан правильно
        (bool initialized,,,,,,,,,) = vesting.vestingSchedules(vestingId);
        assertTrue(initialized);
    }

    function testCreateCliffVestingSchedule() public {
        uint256 startTime = block.timestamp;

        bytes32 vestingId = vesting.createVestingSchedule(
            beneficiary1,
            startTime,
            CLIFF_DURATION,
            VESTING_DURATION,
            1 days,
            VESTING_AMOUNT,
            BAFEXVesting.VestingType.CLIFF
        );

        assertTrue(vestingId != bytes32(0));

        // Проверяем, что в период клиффа токены не доступны
        vm.warp(startTime + CLIFF_DURATION - 1);
        assertEq(vesting.computeReleasableAmount(vestingId), 0);

        // После клиффа токены начинают веститься
        vm.warp(startTime + CLIFF_DURATION + 1);
        assertTrue(vesting.computeReleasableAmount(vestingId) > 0);
    }

    function testLinearVestingRelease() public {
        uint256 startTime = block.timestamp;

        bytes32 vestingId = vesting.createVestingSchedule(
            beneficiary1, startTime, 0, VESTING_DURATION, 1 days, VESTING_AMOUNT, BAFEXVesting.VestingType.LINEAR
        );

        // Переходим на полпути вестинга
        vm.warp(startTime + VESTING_DURATION / 2);

        uint256 releasableAmount = vesting.computeReleasableAmount(vestingId);
        uint256 expectedAmount = VESTING_AMOUNT / 2;

        // Допускаем небольшую погрешность из-за округления
        assertApproxEqRel(releasableAmount, expectedAmount, 0.01e18);

        // Выпускаем токены
        vm.prank(beneficiary1);
        vm.expectEmit(true, false, false, true);
        emit TokensReleased(vestingId, releasableAmount);
        vesting.release(vestingId, releasableAmount);

        assertEq(token.balanceOf(beneficiary1), releasableAmount);
    }

    function testCliffVestingRelease() public {
        uint256 startTime = block.timestamp;

        bytes32 vestingId = vesting.createVestingSchedule(
            beneficiary1,
            startTime,
            CLIFF_DURATION,
            VESTING_DURATION,
            1 days,
            VESTING_AMOUNT,
            BAFEXVesting.VestingType.CLIFF
        );

        // До клиффа токены не доступны
        vm.warp(startTime + CLIFF_DURATION - 1);
        assertEq(vesting.computeReleasableAmount(vestingId), 0);

        // После клиффа токены доступны
        vm.warp(startTime + CLIFF_DURATION + 30 days);
        uint256 releasableAmount = vesting.computeReleasableAmount(vestingId);
        assertTrue(releasableAmount > 0);

        // Выпускаем токены
        vm.prank(beneficiary1);
        vesting.release(vestingId, releasableAmount);
        assertEq(token.balanceOf(beneficiary1), releasableAmount);
    }

    function testReleaseAll() public {
        uint256 startTime = block.timestamp;

        bytes32 vestingId = vesting.createVestingSchedule(
            beneficiary1, startTime, 0, VESTING_DURATION, 1 days, VESTING_AMOUNT, BAFEXVesting.VestingType.LINEAR
        );

        // Переходим к концу вестинга
        vm.warp(startTime + VESTING_DURATION + 1);

        uint256 initialBalance = token.balanceOf(beneficiary1);

        // Выпускаем все токены
        vm.prank(beneficiary1);
        vesting.releaseAll(vestingId);

        assertEq(token.balanceOf(beneficiary1), initialBalance + VESTING_AMOUNT);
    }

    function testRevokeVestingSchedule() public {
        uint256 startTime = block.timestamp;

        bytes32 vestingId = vesting.createVestingSchedule(
            beneficiary1,
            startTime,
            CLIFF_DURATION,
            VESTING_DURATION,
            1 days,
            VESTING_AMOUNT,
            BAFEXVesting.VestingType.CLIFF
        );

        // Переходим к концу вестинга
        vm.warp(startTime + VESTING_DURATION + 1);

        uint256 vestedAmount = vesting.computeReleasableAmount(vestingId);
        uint256 initialBalance = token.balanceOf(beneficiary1);

        // Отзываем план вестинга
        vm.expectEmit(true, false, false, true);
        emit VestingScheduleRevoked(vestingId);
        vesting.revoke(vestingId);

        // Проверяем, что вестинговые токены выпущены
        assertEq(token.balanceOf(beneficiary1), initialBalance + vestedAmount);

        // Проверяем, что план отозван
        vm.expectRevert("BAFEXVesting: vesting schedule revoked");
        vesting.release(vestingId, 1);
    }

    function testMultipleVestingSchedules() public {
        uint256 startTime = block.timestamp;

        // Создаем несколько планов вестинга для одного бенефициара
        bytes32 vestingId1 = vesting.createVestingSchedule(
            beneficiary1, startTime, 0, VESTING_DURATION, 1 days, VESTING_AMOUNT, BAFEXVesting.VestingType.LINEAR
        );

        bytes32 vestingId2 = vesting.createVestingSchedule(
            beneficiary1,
            startTime + 30 days,
            CLIFF_DURATION,
            VESTING_DURATION,
            1 days,
            VESTING_AMOUNT,
            BAFEXVesting.VestingType.CLIFF
        );

        assertEq(vesting.getVestingSchedulesCountByBeneficiary(beneficiary1), 2);
        assertEq(vesting.getVestingScheduleAtIndex(beneficiary1, 0), vestingId1);
        assertEq(vesting.getVestingScheduleAtIndex(beneficiary1, 1), vestingId2);
    }

    function testComputeVestedAmount() public {
        uint256 startTime = block.timestamp;

        bytes32 vestingId = vesting.createVestingSchedule(
            beneficiary1, startTime, 0, VESTING_DURATION, 1 days, VESTING_AMOUNT, BAFEXVesting.VestingType.LINEAR
        );

        // В начале вестинга
        assertEq(vesting.computeVestedAmount(beneficiary1), 0);

        // На полпути
        vm.warp(startTime + VESTING_DURATION / 2);
        uint256 vestedAmount = vesting.computeVestedAmount(beneficiary1);
        uint256 expectedAmount = VESTING_AMOUNT / 2;
        assertApproxEqRel(vestedAmount, expectedAmount, 0.01e18);

        // В конце
        vm.warp(startTime + VESTING_DURATION + 1);
        assertEq(vesting.computeVestedAmount(beneficiary1), VESTING_AMOUNT);
    }

    function testWithdraw() public {
        uint256 withdrawAmount = 1000 * 10 ** 18;
        uint256 initialBalance = token.balanceOf(owner);

        vesting.withdraw(withdrawAmount);

        assertEq(token.balanceOf(owner), initialBalance + withdrawAmount);
    }

    function testOnlyOwnerCanCreateVestingSchedule() public {
        vm.prank(beneficiary1);
        vm.expectRevert();
        vesting.createVestingSchedule(
            beneficiary1, block.timestamp, 0, VESTING_DURATION, 1 days, VESTING_AMOUNT, BAFEXVesting.VestingType.LINEAR
        );
    }

    function testOnlyOwnerCanRevoke() public {
        uint256 startTime = block.timestamp;

        bytes32 vestingId = vesting.createVestingSchedule(
            beneficiary1, startTime, 0, VESTING_DURATION, 1 days, VESTING_AMOUNT, BAFEXVesting.VestingType.LINEAR
        );

        vm.prank(beneficiary1);
        vm.expectRevert();
        vesting.revoke(vestingId);
    }

    function testOnlyOwnerCanWithdraw() public {
        vm.prank(beneficiary1);
        vm.expectRevert();
        vesting.withdraw(1000 * 10 ** 18);
    }

    function testOnlyBeneficiaryOrOwnerCanRelease() public {
        uint256 startTime = block.timestamp;

        bytes32 vestingId = vesting.createVestingSchedule(
            beneficiary1, startTime, 0, VESTING_DURATION, 1 days, VESTING_AMOUNT, BAFEXVesting.VestingType.LINEAR
        );

        vm.warp(startTime + VESTING_DURATION / 2);

        vm.prank(beneficiary2);
        vm.expectRevert("BAFEXVesting: only beneficiary or owner can release");
        vesting.release(vestingId, 1000 * 10 ** 18);
    }

    function testCannotReleaseZeroAmount() public {
        uint256 startTime = block.timestamp;

        bytes32 vestingId = vesting.createVestingSchedule(
            beneficiary1, startTime, 0, VESTING_DURATION, 1 days, VESTING_AMOUNT, BAFEXVesting.VestingType.LINEAR
        );

        vm.warp(startTime + VESTING_DURATION / 2);

        vm.prank(beneficiary1);
        vm.expectRevert("BAFEXVesting: amount must be greater than 0");
        vesting.release(vestingId, 0);
    }

    function testCannotReleaseMoreThanAvailable() public {
        uint256 startTime = block.timestamp;

        bytes32 vestingId = vesting.createVestingSchedule(
            beneficiary1, startTime, 0, VESTING_DURATION, 1 days, VESTING_AMOUNT, BAFEXVesting.VestingType.LINEAR
        );

        vm.warp(startTime + VESTING_DURATION / 2);

        uint256 availableAmount = vesting.computeReleasableAmount(vestingId);

        vm.prank(beneficiary1);
        vm.expectRevert("BAFEXVesting: not enough vested tokens");
        vesting.release(vestingId, availableAmount + 1);
    }

    function testInvalidVestingDuration() public {
        vm.expectRevert("BAFEXVesting: invalid duration");
        vesting.createVestingSchedule(
            beneficiary1,
            block.timestamp,
            0,
            0, // слишком короткий период
            1 days,
            VESTING_AMOUNT,
            BAFEXVesting.VestingType.LINEAR
        );

        vm.expectRevert("BAFEXVesting: invalid duration");
        vesting.createVestingSchedule(
            beneficiary1,
            block.timestamp,
            0,
            365 days * 11, // слишком длинный период
            1 days,
            VESTING_AMOUNT,
            BAFEXVesting.VestingType.LINEAR
        );
    }

    function testInvalidCliffPeriod() public {
        vm.expectRevert("BAFEXVesting: invalid cliff period");
        vesting.createVestingSchedule(
            beneficiary1,
            block.timestamp,
            VESTING_DURATION + 1, // клифф больше чем общий период
            VESTING_DURATION,
            1 days,
            VESTING_AMOUNT,
            BAFEXVesting.VestingType.CLIFF
        );
    }

    function testZeroBeneficiary() public {
        vm.expectRevert("BAFEXVesting: beneficiary cannot be zero address");
        vesting.createVestingSchedule(
            address(0), block.timestamp, 0, VESTING_DURATION, 1 days, VESTING_AMOUNT, BAFEXVesting.VestingType.LINEAR
        );
    }

    function testZeroAmount() public {
        vm.expectRevert("BAFEXVesting: amount must be greater than 0");
        vesting.createVestingSchedule(
            beneficiary1,
            block.timestamp,
            0,
            VESTING_DURATION,
            1 days,
            0, // нулевое количество
            BAFEXVesting.VestingType.LINEAR
        );
    }

    function testComputeVestingScheduleId() public {
        bytes32 id1 = vesting.computeVestingScheduleIdForAddressAndIndex(beneficiary1, 0);
        bytes32 id2 = vesting.computeVestingScheduleIdForAddressAndIndex(beneficiary1, 1);

        assertTrue(id1 != id2);
        assertTrue(id1 != bytes32(0));
        assertTrue(id2 != bytes32(0));
    }
}
