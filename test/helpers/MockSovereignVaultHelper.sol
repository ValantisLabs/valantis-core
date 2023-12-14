// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { MockSovereignVault } from 'test/mocks/MockSovereignVault.sol';

library MockSovereignVaultHelper {
    function deploySovereignVault() internal returns (address) {
        MockSovereignVault vault = new MockSovereignVault();
        return address(vault);
    }

    function toggleExcessFee(address vault, bool state) internal {
        MockSovereignVault(vault).toggleExcessFee(state);
    }

    function setPool(address vault, address pool) internal {
        MockSovereignVault(vault).setPool(pool);
    }

    function toggleInvalidReserveArray(address vault, bool state) internal {
        MockSovereignVault(vault).toggleSendInvalidReservesArray(state);
    }
}
