// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "lib/forge-std/src/Test.sol";
import {BAFEXToken} from "../src/Token.sol";
import {BAFEXDistribution} from "../src/BAFEXDistribution.sol";

/**
 * @title BAFEXDistributionTest
 * @dev Комплексные тесты для контракта распределения BAFEX.
 */
contract BAFEXDistributionTest is Test {
    BAFEXToken public token;
    BAFEXDistribution public distribution;

    address public owner;
    address public recipient1;
    address public recipient2;
    address public recipient3;

    uint256 public constant TEAM_ALLOCATION = 1_000_000 * 10 ** 18; // 1M токенов для команды
    uint256 public constant MARKETING_ALLOCATION = 500_000 * 10 ** 18; // 500K токенов для маркетинга
    uint256 public constant PARTNERS_ALLOCATION = 300_000 * 10 ** 18; // 300K токенов для партнеров

    event CategoryCreated(string indexed categoryName, uint256 allocatedAmount, uint256 maxRecipients);
    event TokensDistributed(string indexed categoryName, address indexed recipient, uint256 amount);
    event BatchDistributionCompleted(string indexed categoryName, uint256 totalAmount, uint256 recipientCount);

    function setUp() public {
        owner = address(this);
        recipient1 = address(0x1);
        recipient2 = address(0x2);
        recipient3 = address(0x3);

        token = new BAFEXToken();
        distribution = new BAFEXDistribution(address(token));

        // Переводим токены в контракт распределения
        token.transfer(address(distribution), 5_000_000 * 10 ** 18);
    }

    function testCreateCategory() public {
        vm.expectEmit(true, false, false, true);
        emit CategoryCreated("Team", TEAM_ALLOCATION, 10);

        distribution.createCategory("Team", TEAM_ALLOCATION, 10);

        (
            string memory name,
            uint256 allocatedAmount,
            uint256 distributedAmount,
            bool isActive,
            uint256 maxRecipients,
            uint256 currentRecipients
        ) = distribution.distributionCategories("Team");
        assertEq(name, "Team");
        assertEq(allocatedAmount, TEAM_ALLOCATION);
        assertEq(distributedAmount, 0);
        assertTrue(isActive);
        assertEq(maxRecipients, 10);
        assertEq(currentRecipients, 0);

        assertEq(distribution.totalAllocated(), TEAM_ALLOCATION);
        assertEq(distribution.getActiveCategoriesCount(), 1);
    }

    function testCreateMultipleCategories() public {
        distribution.createCategory("Team", TEAM_ALLOCATION, 10);
        distribution.createCategory("Marketing", MARKETING_ALLOCATION, 20);
        distribution.createCategory("Partners", PARTNERS_ALLOCATION, 5);

        assertEq(distribution.getActiveCategoriesCount(), 3);
        assertEq(distribution.totalAllocated(), TEAM_ALLOCATION + MARKETING_ALLOCATION + PARTNERS_ALLOCATION);

        string[] memory categoryNames = distribution.getAllCategoryNames();
        assertEq(categoryNames.length, 3);
    }

    function testDistributeToSingleRecipient() public {
        distribution.createCategory("Team", TEAM_ALLOCATION, 10);

        uint256 distributeAmount = 100_000 * 10 ** 18;

        vm.expectEmit(true, true, false, true);
        emit TokensDistributed("Team", recipient1, distributeAmount);

        distribution.distributeToRecipient("Team", recipient1, distributeAmount);

        assertEq(token.balanceOf(recipient1), distributeAmount);
        assertEq(distribution.totalDistributed(), distributeAmount);

        (,,,,, uint256 currentRecipients) = distribution.distributionCategories("Team");
        assertEq(currentRecipients, 1);

        address[] memory recipients = distribution.getCategoryRecipients("Team");
        assertEq(recipients.length, 1);
        assertEq(recipients[0], recipient1);
    }

    function testDistributeBatch() public {
        distribution.createCategory("Team", TEAM_ALLOCATION, 10);

        address[] memory recipients_ = new address[](2);
        recipients_[0] = recipient1;
        recipients_[1] = recipient2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 50_000 * 10 ** 18;
        amounts[1] = 75_000 * 10 ** 18;

        uint256 expectedTotal = amounts[0] + amounts[1];

        vm.expectEmit(true, false, false, true);
        emit BatchDistributionCompleted("Team", expectedTotal, 2);

        distribution.distributeBatch("Team", recipients_, amounts);

        assertEq(token.balanceOf(recipient1), amounts[0]);
        assertEq(token.balanceOf(recipient2), amounts[1]);
        assertEq(distribution.totalDistributed(), expectedTotal);

        assertEq(distribution.getCategoryRecipientsCount("Team"), 2);
    }

    function testDistributeWithCliff() public {
        distribution.createCategory("Team", TEAM_ALLOCATION, 10);

        uint256 distributeAmount = 100_000 * 10 ** 18;

        // Первое распределение
        distribution.distributeToRecipient("Team", recipient1, distributeAmount);
        assertEq(token.balanceOf(recipient1), distributeAmount);

        // Проверяем, что получатель уже распределен
        (address recipient, uint256 amount, bool isDistributed, uint256 distributionTime, string memory categoryName) =
            distribution.recipients(recipient1);
        assertEq(recipient, recipient1);
        assertEq(amount, distributeAmount);
        assertTrue(isDistributed);
        assertEq(distributionTime, block.timestamp);
        assertEq(categoryName, "Team");
    }

    function testPauseAndResumeCategory() public {
        distribution.createCategory("Team", TEAM_ALLOCATION, 10);

        // Паузим категорию
        distribution.pauseCategory("Team");
        (,,, bool isActive,,) = distribution.distributionCategories("Team");
        assertFalse(isActive);

        // Попытка распределения должна провалиться
        vm.expectRevert("BAFEXDistribution: category not active");
        distribution.distributeToRecipient("Team", recipient1, 1000 * 10 ** 18);

        // Возобновляем категорию
        distribution.resumeCategory("Team");
        (,,, bool isActiveAfter,,) = distribution.distributionCategories("Team");
        assertTrue(isActiveAfter);

        // Теперь распределение должно работать
        distribution.distributeToRecipient("Team", recipient1, 1000 * 10 ** 18);
        assertEq(token.balanceOf(recipient1), 1000 * 10 ** 18);
    }

    function testPauseContract() public {
        distribution.createCategory("Team", TEAM_ALLOCATION, 10);

        // Паузим весь контракт
        distribution.pause();

        // Попытка распределения должна провалиться
        vm.expectRevert();
        distribution.distributeToRecipient("Team", recipient1, 1000 * 10 ** 18);

        // Снимаем паузу
        distribution.unpause();

        // Теперь распределение должно работать
        distribution.distributeToRecipient("Team", recipient1, 1000 * 10 ** 18);
        assertEq(token.balanceOf(recipient1), 1000 * 10 ** 18);
    }

    function testWithdrawUnusedTokens() public {
        distribution.createCategory("Team", TEAM_ALLOCATION, 10);

        // Распределяем часть токенов
        distribution.distributeToRecipient("Team", recipient1, 100_000 * 10 ** 18);

        uint256 initialOwnerBalance = token.balanceOf(owner);
        uint256 unusedTokens = distribution.getUnusedTokens();

        distribution.withdrawUnusedTokens(unusedTokens);

        assertEq(token.balanceOf(owner), initialOwnerBalance + unusedTokens);
    }

    function testEmergencyWithdraw() public {
        uint256 initialOwnerBalance = token.balanceOf(owner);
        uint256 distributionBalance = token.balanceOf(address(distribution));

        distribution.emergencyWithdraw();

        assertEq(token.balanceOf(owner), initialOwnerBalance + distributionBalance);
        assertEq(token.balanceOf(address(distribution)), 0);
    }

    function testOnlyOwnerCanCreateCategory() public {
        vm.prank(recipient1);
        vm.expectRevert();
        distribution.createCategory("Team", TEAM_ALLOCATION, 10);
    }

    function testOnlyOwnerCanDistribute() public {
        distribution.createCategory("Team", TEAM_ALLOCATION, 10);

        vm.prank(recipient1);
        vm.expectRevert();
        distribution.distributeToRecipient("Team", recipient2, 1000 * 10 ** 18);
    }

    function testOnlyOwnerCanWithdraw() public {
        vm.prank(recipient1);
        vm.expectRevert();
        distribution.withdrawUnusedTokens(1000 * 10 ** 18);
    }

    function testCannotDistributeToZeroAddress() public {
        distribution.createCategory("Team", TEAM_ALLOCATION, 10);

        vm.expectRevert("BAFEXDistribution: recipient cannot be zero address");
        distribution.distributeToRecipient("Team", address(0), 1000 * 10 ** 18);
    }

    function testCannotDistributeZeroAmount() public {
        distribution.createCategory("Team", TEAM_ALLOCATION, 10);

        vm.expectRevert("BAFEXDistribution: amount must be greater than 0");
        distribution.distributeToRecipient("Team", recipient1, 0);
    }

    function testCannotExceedCategoryAllocation() public {
        distribution.createCategory("Team", TEAM_ALLOCATION, 10);

        vm.expectRevert("BAFEXDistribution: insufficient category allocation");
        distribution.distributeToRecipient("Team", recipient1, TEAM_ALLOCATION + 1);
    }

    function testCannotExceedMaxRecipients() public {
        distribution.createCategory("Team", 1000 * 10 ** 18, 1); // Максимум 1 получатель

        distribution.distributeToRecipient("Team", recipient1, 500 * 10 ** 18);

        vm.expectRevert("BAFEXDistribution: max recipients reached");
        distribution.distributeToRecipient("Team", recipient2, 500 * 10 ** 18);
    }

    function testCannotDistributeToSameRecipientTwice() public {
        distribution.createCategory("Team", TEAM_ALLOCATION, 10);

        distribution.distributeToRecipient("Team", recipient1, 1000 * 10 ** 18);

        vm.expectRevert("BAFEXDistribution: recipient already distributed");
        distribution.distributeToRecipient("Team", recipient1, 1000 * 10 ** 18);
    }

    function testBatchDistributionValidation() public {
        distribution.createCategory("Team", TEAM_ALLOCATION, 10);

        address[] memory recipients_ = new address[](2);
        recipients_[0] = recipient1;
        recipients_[1] = recipient2;

        uint256[] memory amounts = new uint256[](3); // Разная длина

        vm.expectRevert("BAFEXDistribution: arrays length mismatch");
        distribution.distributeBatch("Team", recipients_, amounts);
    }

    function testEmptyBatchDistribution() public {
        distribution.createCategory("Team", TEAM_ALLOCATION, 10);

        address[] memory recipients_ = new address[](0);
        uint256[] memory amounts = new uint256[](0);

        vm.expectRevert("BAFEXDistribution: empty batch");
        distribution.distributeBatch("Team", recipients_, amounts);
    }

    function testBatchTooLarge() public {
        distribution.createCategory("Team", TEAM_ALLOCATION, 200); // Больше MAX_BATCH_SIZE

        address[] memory recipients_ = new address[](101); // Больше MAX_BATCH_SIZE
        uint256[] memory amounts = new uint256[](101);

        for (uint256 i = 0; i < 101; i++) {
            recipients_[i] = address(uint160(i + 100)); // Уникальные адреса
            amounts[i] = 1000 * 10 ** 18;
        }

        vm.expectRevert("BAFEXDistribution: batch too large");
        distribution.distributeBatch("Team", recipients_, amounts);
    }

    function testInsufficientTokenBalance() public {
        // Создаем категорию с количеством токенов больше, чем есть в контракте
        uint256 largeAllocation = token.balanceOf(address(distribution)) + 1;

        vm.expectRevert("BAFEXDistribution: insufficient token balance");
        distribution.createCategory("Team", largeAllocation, 10);
    }

    function testCategoryNameValidation() public {
        vm.expectRevert("BAFEXDistribution: category name cannot be empty");
        distribution.createCategory("", TEAM_ALLOCATION, 10);
    }

    function testMinAllocationValidation() public {
        vm.expectRevert("BAFEXDistribution: insufficient allocation");
        distribution.createCategory("Team", 100, 10); // Меньше MIN_ALLOCATION
    }

    function testMaxRecipientsValidation() public {
        vm.expectRevert("BAFEXDistribution: max recipients must be greater than 0");
        distribution.createCategory("Team", TEAM_ALLOCATION, 0);
    }

    function testDuplicateCategory() public {
        distribution.createCategory("Team", TEAM_ALLOCATION, 10);

        vm.expectRevert("BAFEXDistribution: category already exists");
        distribution.createCategory("Team", MARKETING_ALLOCATION, 5);
    }

    function testMaxCategoriesLimit() public {
        // Создаем максимальное количество категорий
        for (uint256 i = 0; i < 20; i++) {
            distribution.createCategory(string(abi.encodePacked("Category", i)), 1000 * 10 ** 18, 1);
        }

        vm.expectRevert("BAFEXDistribution: too many categories");
        distribution.createCategory("Category21", 1000 * 10 ** 18, 1);
    }

    function testGetCategoryInfo() public {
        distribution.createCategory("Team", TEAM_ALLOCATION, 10);

        (
            string memory name,
            uint256 allocatedAmount,
            uint256 distributedAmount,
            bool isActive,
            uint256 maxRecipients,
            uint256 currentRecipients
        ) = distribution.distributionCategories("Team");

        assertEq(name, "Team");
        assertEq(allocatedAmount, TEAM_ALLOCATION);
        assertEq(distributedAmount, 0);
        assertTrue(isActive);
        assertEq(maxRecipients, 10);
        assertEq(currentRecipients, 0);
    }

    function testComplexDistributionScenario() public {
        // Создаем несколько категорий
        distribution.createCategory("Team", TEAM_ALLOCATION, 5);
        distribution.createCategory("Marketing", MARKETING_ALLOCATION, 10);
        distribution.createCategory("Partners", PARTNERS_ALLOCATION, 3);

        // Распределяем токены команде
        distribution.distributeToRecipient("Team", recipient1, 200_000 * 10 ** 18);
        distribution.distributeToRecipient("Team", recipient2, 150_000 * 10 ** 18);

        // Распределяем токены маркетингу
        address[] memory marketingRecipients = new address[](2);
        marketingRecipients[0] = recipient1; // recipient1 получает и от команды, и от маркетинга
        marketingRecipients[1] = recipient3;

        uint256[] memory marketingAmounts = new uint256[](2);
        marketingAmounts[0] = 100_000 * 10 ** 18;
        marketingAmounts[1] = 50_000 * 10 ** 18;

        // Это должно провалиться, так как recipient1 уже получал токены
        vm.expectRevert("BAFEXDistribution: recipient already distributed");
        distribution.distributeBatch("Marketing", marketingRecipients, marketingAmounts);

        // Исправляем - убираем recipient1
        marketingRecipients[0] = address(0x4);
        distribution.distributeBatch("Marketing", marketingRecipients, marketingAmounts);

        // Проверяем итоговые балансы
        assertEq(token.balanceOf(recipient1), 200_000 * 10 ** 18); // Только от команды
        assertEq(token.balanceOf(recipient2), 150_000 * 10 ** 18); // Только от команды
        assertEq(token.balanceOf(recipient3), 50_000 * 10 ** 18); // Только от маркетинга
        assertEq(token.balanceOf(address(0x4)), 100_000 * 10 ** 18); // Только от маркетинга

        // Проверяем статистику
        assertEq(distribution.getCategoryRecipientsCount("Team"), 2);
        assertEq(distribution.getCategoryRecipientsCount("Marketing"), 2);
        assertEq(distribution.getCategoryRecipientsCount("Partners"), 0);
        assertEq(distribution.getActiveCategoriesCount(), 3);
    }
}
