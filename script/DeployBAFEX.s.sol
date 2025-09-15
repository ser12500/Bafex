// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "lib/forge-std/src/Script.sol";
import "../src/Token.sol";
import "../src/BAFEXVesting.sol";
import "../src/BAFEXDistribution.sol";
import "../src/BAFEXStaking.sol";

contract DeployBAFEX is Script {
    function run() external {
        vm.startBroadcast();

        // Деплой токена BAFEX
        BAFEXToken token = new BAFEXToken();
        console.log("BAFEXToken deployed at:", address(token));

        // Деплой контракта вестинга
        BAFEXVesting vesting = new BAFEXVesting(address(token));
        console.log("BAFEXVesting deployed at:", address(vesting));

        // Деплой контракта распределения
        BAFEXDistribution distribution = new BAFEXDistribution(address(token));
        console.log("BAFEXDistribution deployed at:", address(distribution));

        // Деплой контракта стейкинга
        BAFEXStaking staking = new BAFEXStaking(address(token));
        console.log("BAFEXStaking deployed at:", address(staking));

        // Переводим токены в контракты
        uint256 vestingAmount = token.totalSupply() * 20 / 100; // 20% для вестинга
        uint256 distributionAmount = token.totalSupply() * 15 / 100; // 15% для распределения
        uint256 stakingRewardsAmount = token.totalSupply() * 10 / 100; // 10% для наград стейкинга

        token.transfer(address(vesting), vestingAmount);
        token.transfer(address(distribution), distributionAmount);
        token.transfer(address(staking), stakingRewardsAmount);

        // Пополняем резерв наград для стейкинга
        staking.addRewardsReserve(stakingRewardsAmount);

        console.log("Transferred", vestingAmount / 10 ** 18, "tokens to vesting contract");
        console.log("Transferred", distributionAmount / 10 ** 18, "tokens to distribution contract");
        console.log("Transferred", stakingRewardsAmount / 10 ** 18, "tokens to staking rewards");

        vm.stopBroadcast();

        console.log("=== Deployment Summary ===");
        console.log("BAFEXToken:", address(token));
        console.log("BAFEXVesting:", address(vesting));
        console.log("BAFEXDistribution:", address(distribution));
        console.log("BAFEXStaking:", address(staking));
        console.log("Vesting Amount:", vestingAmount / 10 ** 18, "BAFEX");
        console.log("Distribution Amount:", distributionAmount / 10 ** 18, "BAFEX");
        console.log("Staking Rewards:", stakingRewardsAmount / 10 ** 18, "BAFEX");
        console.log("Owner Balance:", token.balanceOf(msg.sender) / 10 ** 18, "BAFEX");
    }
}
