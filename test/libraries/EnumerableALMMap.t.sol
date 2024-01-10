// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { Test } from 'forge-std/Test.sol';
import { console } from 'forge-std/console.sol';

import { EnumerableALMMap } from 'src/libraries/EnumerableALMMap.sol';
import { ALMPosition, Slot0, ALMStatus, ALMReserves } from 'src/pools/structs/UniversalPoolStructs.sol';

contract EnumerableALMMapTest is Test {
    using EnumerableALMMap for EnumerableALMMap.ALMSet;

    EnumerableALMMap.ALMSet ALMPositions;

    /************************************************
     *  Test Functions
     ***********************************************/

    function test_add(uint256 numBaseALM, uint256 numMetaALM) public {
        numBaseALM = bound(numBaseALM, 0, 256);
        numMetaALM = bound(numMetaALM, 0, 256);

        vm.assume(numBaseALM + numMetaALM <= 256);

        _prepareSet(numBaseALM, numMetaALM);

        bool encounteredMetaALM;
        for (uint256 i; i < numBaseALM + numMetaALM; i++) {
            Slot0 memory almSlot = ALMPositions.getSlot0(i);

            if (almSlot.isMetaALM) {
                encounteredMetaALM = true;
            } else {
                assert(!encounteredMetaALM);
            }
        }

        ALMPosition[] memory alms = ALMPositions.values();
        bool[] memory indexFlags = new bool[](numBaseALM + numMetaALM);

        for (uint256 i; i < numBaseALM + numMetaALM; i++) {
            indexFlags[uint256(uint160(alms[i].slot0.almAddress)) - 1] = true;
        }

        for (uint256 i; i < numBaseALM + numMetaALM; i++) {
            assertEq(indexFlags[i], true);
        }
        if (numBaseALM + numMetaALM != 0) {
            vm.expectRevert(EnumerableALMMap.EnumerableALMMap__invalidALMAddress.selector);
            ALMPositions.add(ALMPosition(Slot0(false, true, true, 0, address(uint160(0))), 0, 0, 0, 0));
        }
    }

    function test_remove(uint256 numBaseALM, uint256 numMetaALM, uint256 removeIndex) public {
        numBaseALM = bound(numBaseALM, 0, 256);
        numMetaALM = bound(numMetaALM, 0, 256);
        vm.assume(numBaseALM + numMetaALM <= 256);
        vm.assume(numBaseALM + numMetaALM != 0);

        removeIndex = bound(removeIndex, 0, numBaseALM + numMetaALM - 1);

        _prepareSet(numBaseALM, numMetaALM);

        ALMPosition[] memory almValuesPreRemove = ALMPositions.values();
        uint256 len = ALMPositions.length();
        (ALMStatus status, ALMPosition memory almPosition) = ALMPositions.getALM(address(uint160(removeIndex + 1)));

        assert(status == ALMStatus.ACTIVE);

        ALMPositions.remove(address(uint160(removeIndex + 1)));

        assertEq(ALMPositions.length(), len - 1);
        if (almPosition.slot0.isMetaALM) {
            assertEq(ALMPositions.getNumBaseALMs(), numBaseALM);
        } else {
            assertEq(ALMPositions.getNumBaseALMs(), numBaseALM - 1);
        }
        (ALMStatus newStatus, ) = ALMPositions.getALM(address(uint160(removeIndex + 1)));

        assert(newStatus == ALMStatus.REMOVED);

        ALMPosition[] memory almValuesPostRemove = ALMPositions.values();

        bool encounteredDeletedElement;
        for (uint256 i; i < numBaseALM + numMetaALM - 1; i++) {
            if (almValuesPreRemove[i].slot0.almAddress == address(uint160(removeIndex + 1))) {
                encounteredDeletedElement = true;
            }

            if (!encounteredDeletedElement) {
                assertEq(almValuesPreRemove[i].slot0.almAddress, almValuesPostRemove[i].slot0.almAddress);
            } else {
                assertEq(almValuesPreRemove[i + 1].slot0.almAddress, almValuesPostRemove[i].slot0.almAddress);
            }
        }

        vm.expectRevert(EnumerableALMMap.EnumerableALMMap__removeALMPosition.selector);
        ALMPositions.remove(address(uint160(removeIndex + 1)));
    }

    function test_isActive(uint256 numBaseALM, uint256 numMetaALM, uint256 setIndex) public {
        numBaseALM = bound(numBaseALM, 0, 256);
        numMetaALM = bound(numMetaALM, 0, 256);

        vm.assume(numBaseALM + numMetaALM <= 256);
        vm.assume(numBaseALM + numMetaALM != 0);

        setIndex = bound(setIndex, 0, numBaseALM + numMetaALM - 1);

        _prepareSet(numBaseALM, numMetaALM);

        assert(ALMPositions.isALMActive(address(uint160(setIndex + 1))));
        ALMPositions.remove(address(uint160(setIndex + 1)));
        assertFalse(ALMPositions.isALMActive(address(uint160(setIndex + 1))), 'ALM has not been removed');
    }

    function test_setMetaALMFeeShare() public {
        uint256 snapshot = vm.snapshot();

        _prepareSet(0, 1);
        address almAddress = address(uint160(0));
        vm.expectRevert(EnumerableALMMap.EnumerableALMMap__highMetaALMFeeShare.selector);
        ALMPositions.setMetaALMFeeShare(almAddress, 5001);

        ALMPositions.setMetaALMFeeShare(almAddress, 5000);
        (ALMStatus status, ALMPosition memory almPosition) = ALMPositions.getALM(almAddress);
        assert(status == ALMStatus.ACTIVE);
        assertEq(almPosition.slot0.metaALMFeeShare, 5000);

        vm.revertTo(snapshot);

        _prepareSet(1, 0);

        vm.expectRevert(EnumerableALMMap.EnumerableALMMap__setMetaALMFeeShare_notMetaALM.selector);
        ALMPositions.setMetaALMFeeShare(address(uint160(0)), 5000);
    }

    function test_getALM() public {
        _prepareSet(1, 1);

        // Checking the null case
        vm.expectRevert(EnumerableALMMap.EnumerableALMMap__almNotFound.selector);
        (ALMStatus status, ALMPosition memory almPosition) = ALMPositions.getALM(address(uint160(3)));

        // Checking the active case
        (status, almPosition) = ALMPositions.getALM(address(uint160(1)));
        assert(status == ALMStatus.ACTIVE);
        assertEq(almPosition.slot0.almAddress, address(1));

        (status, almPosition) = ALMPositions.getALM(address(uint160(2)));
        assert(status == ALMStatus.ACTIVE);
        assertEq(almPosition.slot0.almAddress, address(2));

        // Checking the remove case
        ALMPositions.remove(address(uint160(1)));
        (status, almPosition) = ALMPositions.getALM(address(uint160(1)));
        assert(status == ALMStatus.REMOVED);
        assertEq(almPosition.slot0.almAddress, address(0));
    }

    function test_hardcodedAdd() public {
        assertEq(ALMPositions.length(), 0);
        assertEq(ALMPositions.values().length, 0);
        assertEq(ALMPositions.getNumBaseALMs(), 0);

        // Add a Base ALM
        ALMPositions.add(ALMPosition(Slot0(false, true, true, 0, address(uint160(1))), 0, 0, 0, 1));
        assertEq(ALMPositions.length(), 1);
        assertEq(ALMPositions.values().length, 1);
        assertEq(ALMPositions.values()[0].slot0.almAddress, address(uint160(1)));
        assertEq(ALMPositions.getNumBaseALMs(), 1);

        // Add a Base ALM - Revert because it cannot have a Meta ALM fee share
        vm.expectRevert(EnumerableALMMap.EnumerableALMMap__baseALMHasPositiveFeeShare.selector);
        ALMPositions.add(ALMPosition(Slot0(false, true, true, 1, address(uint160(2))), 0, 0, 0, 1));

        // Add a Base ALM - Revert because zero address is invalid
        vm.expectRevert(EnumerableALMMap.EnumerableALMMap__invalidALMAddress.selector);
        ALMPositions.add(ALMPosition(Slot0(false, true, true, 0, address(uint160(0))), 0, 0, 0, 1));

        // Add a Meta ALM
        ALMPositions.add(ALMPosition(Slot0(true, true, false, 1, address(uint160(2))), 0, 0, 0, 2));
        assertEq(ALMPositions.length(), 2);
        assertEq(ALMPositions.values().length, 2);
        assertEq(ALMPositions.values()[1].slot0.almAddress, address(uint160(2)));
        assertEq(ALMPositions.getNumBaseALMs(), 1);

        // Add a Meta ALM - Revert because Meta ALMs cannot share quotes
        vm.expectRevert(EnumerableALMMap.EnumerableALMMap__metaALMCannotShareQuotes.selector);
        ALMPositions.add(ALMPosition(Slot0(true, true, true, 1, address(uint160(3))), 0, 0, 0, 2));

        // Add a Meta ALM - Revert because of excessive Meta ALM fee share
        vm.expectRevert(EnumerableALMMap.EnumerableALMMap__highMetaALMFeeShare.selector);
        ALMPositions.add(ALMPosition(Slot0(true, true, true, 5001, address(uint160(3))), 0, 0, 0, 2));

        // Add a Base ALM
        ALMPositions.add(ALMPosition(Slot0(false, true, true, 0, address(uint160(3))), 0, 0, 0, 3));
        assertEq(ALMPositions.length(), 3);
        assertEq(ALMPositions.values().length, 3);
        assertEq(ALMPositions.values()[1].slot0.almAddress, address(uint160(3)));
        assertEq(ALMPositions.values()[2].slot0.almAddress, address(uint160(2)));
        assertEq(ALMPositions.getNumBaseALMs(), 2);

        // Remove a Base ALM
        (ALMStatus status, ALMPosition memory alm) = ALMPositions.getALM(address(uint160(3)));
        ALMPositions.remove(address(uint160(3)));
        assertEq(ALMPositions.length(), 2);
        assertEq(ALMPositions.values().length, 2);
        assertEq(ALMPositions.values()[0].slot0.almAddress, address(uint160(1)));
        assertEq(ALMPositions.values()[1].slot0.almAddress, address(uint160(2)));
        assertEq(ALMPositions.getNumBaseALMs(), 1);
        (status, alm) = ALMPositions.getALM(address(uint160(3)));
        assert(status == ALMStatus.REMOVED);
        assertEq(alm.slot0.almAddress, address(uint160(3)));

        // Remove a Meta ALM
        ALMPositions.remove(address(uint160(2)));
        assertEq(ALMPositions.length(), 1);
        assertEq(ALMPositions.values().length, 1);
        assertEq(ALMPositions.values()[0].slot0.almAddress, address(uint160(1)));
        assertEq(ALMPositions.getNumBaseALMs(), 1);
        (status, alm) = ALMPositions.getALM(address(uint160(2)));
        assert(status == ALMStatus.REMOVED);
        assertEq(alm.slot0.almAddress, address(uint160(2)));
    }

    function test_getSlot0() public {
        ALMPositions.add(ALMPosition(Slot0(false, true, true, 0, address(uint160(1))), 0, 0, 0, 1));
        vm.expectRevert(EnumerableALMMap.EnumerableALMMap__almNotFound.selector);
        ALMPositions.getSlot0(1);

        Slot0 memory slot0 = ALMPositions.getSlot0(0);
        assertEq(slot0.almAddress, address(uint160(1)));

        ALMPositions.remove(address(uint160(1)));
        vm.expectRevert(EnumerableALMMap.EnumerableALMMap__almNotFound.selector);
        ALMPositions.getSlot0(0);
    }

    function test_updateReserves() public {
        ALMReserves memory reserves = ALMReserves(30, 25);
        ALMPositions.add(ALMPosition(Slot0(false, true, true, 0, address(uint160(1))), 0, 0, 0, 0));
        // Revert Case
        vm.expectRevert(EnumerableALMMap.EnumerableALMMap__almNotFound.selector);
        ALMPositions.updateReservesPostSwap(true, address(uint160(2)), reserves, 5);

        // Correct Case
        (, ALMPosition memory position) = ALMPositions.getALM(address(uint160(1)));
        ALMPositions.updateReservesPostSwap(true, address(uint160(1)), reserves, 5);
        (, position) = ALMPositions.getALM(address(uint160(1)));

        assertEq(position.reserve0, 30);
        assertEq(position.reserve1, 25);
        assertEq(position.feeCumulative0, 5);
        assertEq(position.feeCumulative1, 0);
    }

    /************************************************
     *  Internal Functions
     ***********************************************/

    function _prepareSet(uint256 numBaseALM, uint256 numMetaALM) internal {
        for (uint256 i; i < numMetaALM; i++) {
            ALMPositions.add(
                ALMPosition(Slot0(true, true, false, 0, address(uint160(1 + i + numBaseALM))), 0, 0, 0, i)
            );
        }

        assertEq(ALMPositions.getNumBaseALMs(), 0);
        for (uint256 i; i < numBaseALM; i++) {
            ALMPositions.add(ALMPosition(Slot0(false, true, true, 0, address(uint160(1 + i))), 0, 0, 0, i));
        }
        assertEq(ALMPositions.getNumBaseALMs(), numBaseALM);

        assertEq(numBaseALM + numMetaALM, ALMPositions.length());
    }
}
