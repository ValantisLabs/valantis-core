// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { ERC20 } from 'lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol';

contract MockTokenDecimal is ERC20 {
    uint8 internalDecimals;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) ERC20(_name, _symbol) {
        internalDecimals = _decimals;
    }

    function decimals() public view virtual override returns (uint8) {
        return internalDecimals;
    }
}
