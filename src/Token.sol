// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title BAFEXToken
 * @dev BEP-20 токен для Binance Smart Chain (BSC).
 * Фиксированная эмиссия: 10 млрд токенов с 18 знаками после запятой.
 * Поддерживает сжигание токенов для дефляционной модели.
 * Наследует от ERC20, ERC20Burnable и Ownable из OpenZeppelin для безопасности.
 */
contract BAFEXToken is ERC20, ERC20Burnable, Ownable {
    /**
     * @dev Конструктор инициализирует токен с именем, символом и полной эмиссией.
     * Все токены минтятся владельцу (деплоеру).
     */
    constructor() ERC20("BAFEX Token", "BAFEX") Ownable(msg.sender) {
        _mint(msg.sender, 10_000_000_000 * 10 ** decimals());
    }

    /**
     * @dev Переопределяет decimals для фиксации в 18.
     */
    function decimals() public pure override returns (uint8) {
        return 18;
    }

    /**
     * @dev Возвращает владельца (для совместимости с BEP-20).
     */
    function getOwner() external view returns (address) {
        return owner();
    }

    /**
     * @dev Сжигает токены от имени владельца контракта.
     * @param amount Количество токенов для сжигания (в wei).
     * Только владелец контракта может вызывать эту функцию.
     */
    function burnFromOwner(uint256 amount) external onlyOwner {
        require(amount > 0, "BAFEX: amount must be greater than 0");
        require(balanceOf(owner()) >= amount, "BAFEX: insufficient balance");
        _burn(owner(), amount);
    }

    /**
     * @dev Сжигает все токены владельца контракта.
     * Только владелец контракта может вызывать эту функцию.
     */
    function burnAllFromOwner() external onlyOwner {
        uint256 balance = balanceOf(owner());
        require(balance > 0, "BAFEX: no tokens to burn");
        _burn(owner(), balance);
    }

    /**
     * @dev Возвращает общее количество сожженных токенов.
     * @return Количество сожженных токенов.
     */
    function totalBurned() external view returns (uint256) {
        uint256 initialSupply = 10_000_000_000 * 10 ** decimals();
        return initialSupply - totalSupply();
    }
}
