// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { ERC20 } from '../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol';
import { Math } from '../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol';

contract MockRebaseToken is ERC20 {
    uint256 public factor = 1e18;
    uint256 public constant NORMALIZER = 1e18;
    bool roundUp = false;
    uint256 roundingError = 0;

    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {}

    function setFactor(uint256 _factor) external {
        require(_factor > 0);
        factor = _factor;
    }

    function setRoundUp(bool _roundUp) external {
        roundUp = _roundUp;
    }

    function setRoundingError(uint256 _roundingError) external {
        roundingError = _roundingError;
    }

    function balanceOf(address _account) public view virtual override returns (uint256) {
        return Math.mulDiv(super.balanceOf(_account), factor, NORMALIZER);
    }

    function _transfer(address from, address to, uint256 amount) internal virtual override {
        uint256 normalizedAmount = Math.mulDiv(amount, NORMALIZER, factor);

        if (normalizedAmount > roundingError) {
            super._transfer(
                from,
                to,
                roundUp ? (normalizedAmount + roundingError) : (normalizedAmount - roundingError)
            );
        } else {
            super._transfer(from, to, normalizedAmount);
        }
    }
}
