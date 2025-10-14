// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "lib/forge-std/src/Script.sol";
import "../src/Token.sol";
import "../src/BAFEXVesting.sol";
import "../src/BAFEXDistribution.sol";
import "../src/BAFEXStaking.sol";
import "../src/BAFEXPaymentGateway.sol";

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

        // Деплой платежного шлюза
        BAFEXPaymentGateway gateway = new BAFEXPaymentGateway();
        console.log("BAFEXPaymentGateway deployed at:", address(gateway));

    
        address USDT = address(0x55d398326f99059ff775485246999027b3197955);    
        address USDC = address(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);  
        gateway.allowToken(address(token), true); // BAFEX
        gateway.allowToken(USDT, true); // USDT
        gateway.allowToken(USDC, true); // USDC

        // Переводим токены в контракты
        uint256 vestingAmount = token.totalSupply() * 20 / 100; // 20% для вестинга
        uint256 distributionAmount = token.totalSupply() * 15 / 100; // 15% для распределения
        uint256 stakingRewardsAmount = token.totalSupply() * 10 / 100; // 10% для стейкинга

        token.transfer(address(vesting), vestingAmount);
        token.transfer(address(distribution), distributionAmount);
        token.transfer(address(staking), stakingRewardsAmount);
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
        console.log("BAFEXPaymentGateway:", address(gateway));
        console.log("Vesting Amount:", vestingAmount / 10 ** 18, "BAFEX");
        console.log("Distribution Amount:", distributionAmount / 10 ** 18, "BAFEX");
        console.log("Staking Rewards:", stakingRewardsAmount / 10 ** 18, "BAFEX");
        console.log("Owner Balance:", token.balanceOf(msg.sender) / 10 ** 18, "BAFEX");
    }
}
