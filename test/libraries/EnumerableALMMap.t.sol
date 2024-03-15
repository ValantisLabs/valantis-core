// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { Test } from 'forge-std/Test.sol';
import { console } from 'forge-std/console.sol';

import { EnumerableALMMap } from 'src/libraries/EnumerableALMMap.sol';
import { ALMPosition, Slot0, ALMStatus, ALMReserves } from 'src/pools/structs/UniversalPoolStructs.sol';

contract Harness {
    EnumerableALMMap.ALMSet public ALMPositions;

    function add(ALMPosition memory _alm) external {
        EnumerableALMMap.add(ALMPositions, _alm);
    }

    function remove(address _almAddress) external {
        EnumerableALMMap.remove(ALMPositions, _almAddress);
    }

    function length() external view returns (uint256) {
        uint256 result = EnumerableALMMap.length(ALMPositions);
        return result;
    }

    function values() external view returns (ALMPosition[] memory) {
        ALMPosition[] memory result = EnumerableALMMap.values(ALMPositions);
        return result;
    }

    function getALM(address almAddress) external view returns (ALMStatus, ALMPosition memory) {
        (ALMStatus status, ALMPosition memory almPosition) = EnumerableALMMap.getALM(ALMPositions, almAddress);
        return (status, almPosition);
    }

    function getSlot0(uint256 index) external view returns (Slot0 memory) {
        Slot0 memory slot = EnumerableALMMap.getSlot0(ALMPositions, index);
        return slot;
    }

    function getNumBaseALMs() external view returns (uint256) {
        uint256 num = EnumerableALMMap.getNumBaseALMs(ALMPositions);
        return num;
    }

    function getALMReserves(bool isZeroToOne, address almAddress) external view returns (ALMReserves memory) {
        ALMReserves memory reserves = EnumerableALMMap.getALMReserves(ALMPositions, isZeroToOne, almAddress);
        return reserves;
    }

    function setMetaALMFeeShare(address almAddress, uint64 newFeeShare) external {
        EnumerableALMMap.setMetaALMFeeShare(ALMPositions, almAddress, newFeeShare);
    }

    function isALMActive(address almAddress) external view returns (bool) {
        bool result = EnumerableALMMap.isALMActive(ALMPositions, almAddress);
        return result;
    }

    function updateReservesPostSwap(
        bool isZeroToOne,
        address almAddress,
        ALMReserves memory almReserves,
        uint256 fee
    ) external {
        EnumerableALMMap.updateReservesPostSwap(ALMPositions, isZeroToOne, almAddress, almReserves, fee);
    }
}

contract EnumerableALMMapTest is Test {
    using EnumerableALMMap for EnumerableALMMap.ALMSet;

    EnumerableALMMap.ALMSet ALMPositions;

    Harness harness;

    function setUp() public {
        harness = new Harness();
    }

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
            Slot0 memory almSlot = harness.getSlot0(i);

            if (almSlot.isMetaALM) {
                encounteredMetaALM = true;
            } else {
                assert(!encounteredMetaALM);
            }
        }

        ALMPosition[] memory alms = harness.values();
        bool[] memory indexFlags = new bool[](numBaseALM + numMetaALM);

        for (uint256 i; i < numBaseALM + numMetaALM; i++) {
            indexFlags[uint256(uint160(alms[i].slot0.almAddress)) - 1] = true;
        }

        for (uint256 i; i < numBaseALM + numMetaALM; i++) {
            assertEq(indexFlags[i], true);
        }
        if (numBaseALM + numMetaALM != 0) {
            vm.expectRevert(EnumerableALMMap.EnumerableALMMap__invalidALMAddress.selector);
            harness.add(ALMPosition(Slot0(false, true, true, 0, address(uint160(0))), 0, 0, 0, 0));
        }

        uint256 num = harness.length();
        while (true) {
            if (harness.length() == 256) {
                vm.expectRevert(EnumerableALMMap.EnumerableALMMap__addALMPosition.selector);
                harness.add(ALMPosition(Slot0(false, true, true, 0, address(uint160(1 + num))), 0, 0, 0, num));
                break;
            }

            harness.add(ALMPosition(Slot0(false, true, true, 0, address(uint160(1 + num))), 0, 0, 0, num));
            num++;
        }
    }

    function test_remove(uint256 numBaseALM, uint256 numMetaALM, uint256 removeIndex) public {
        numBaseALM = bound(numBaseALM, 0, 256);
        numMetaALM = bound(numMetaALM, 0, 256);
        vm.assume(numBaseALM + numMetaALM <= 256);
        vm.assume(numBaseALM + numMetaALM != 0);

        removeIndex = bound(removeIndex, 0, numBaseALM + numMetaALM - 1);

        _prepareSet(numBaseALM, numMetaALM);

        ALMPosition[] memory almValuesPreRemove = harness.values();
        uint256 len = harness.length();
        (ALMStatus status, ALMPosition memory almPosition) = harness.getALM(address(uint160(removeIndex + 1)));

        assert(status == ALMStatus.ACTIVE);

        harness.remove(address(uint160(removeIndex + 1)));

        assertEq(harness.length(), len - 1);
        if (almPosition.slot0.isMetaALM) {
            assertEq(harness.getNumBaseALMs(), numBaseALM);
        } else {
            assertEq(harness.getNumBaseALMs(), numBaseALM - 1);
        }
        (ALMStatus newStatus, ) = harness.getALM(address(uint160(removeIndex + 1)));

        assert(newStatus == ALMStatus.REMOVED);

        ALMPosition[] memory almValuesPostRemove = harness.values();

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

        vm.expectRevert(EnumerableALMMap.EnumerableALMMap__removeALMPosition_almNotFound.selector);
        harness.remove(address(uint160(removeIndex + 1)));

        // Can not add removed ALM again
        vm.expectRevert(EnumerableALMMap.EnumerableALMMap__addALMPosition_almAlreadyExists.selector);
        harness.add(ALMPosition(Slot0(false, true, true, 0, address(uint160(removeIndex + 1))), 0, 0, 0, removeIndex));
    }

    function test_isActive(uint256 numBaseALM, uint256 numMetaALM, uint256 setIndex) public {
        numBaseALM = bound(numBaseALM, 0, 256);
        numMetaALM = bound(numMetaALM, 0, 256);

        vm.assume(numBaseALM + numMetaALM <= 256);
        vm.assume(numBaseALM + numMetaALM != 0);

        setIndex = bound(setIndex, 0, numBaseALM + numMetaALM - 1);

        _prepareSet(numBaseALM, numMetaALM);

        assert(harness.isALMActive(address(uint160(setIndex + 1))));
        harness.remove(address(uint160(setIndex + 1)));
        assertFalse(harness.isALMActive(address(uint160(setIndex + 1))), 'ALM has not been removed');
    }

    function test_setMetaALMFeeShare() public {
        uint256 snapshot = vm.snapshot();

        _prepareSet(0, 1);
        address almAddress = address(uint160(1));
        vm.expectRevert(EnumerableALMMap.EnumerableALMMap__highMetaALMFeeShare.selector);
        harness.setMetaALMFeeShare(almAddress, 5001);

        harness.setMetaALMFeeShare(almAddress, 5000);
        (ALMStatus status, ALMPosition memory almPosition) = harness.getALM(almAddress);
        assert(status == ALMStatus.ACTIVE);
        assertEq(almPosition.slot0.metaALMFeeShare, 5000);

        vm.revertTo(snapshot);

        _prepareSet(1, 0);

        vm.expectRevert(EnumerableALMMap.EnumerableALMMap__setMetaALMFeeShare_notMetaALM.selector);
        harness.setMetaALMFeeShare(address(uint160(1)), 5000);
    }

    function test_getALM() public {
        _prepareSet(1, 1);

        // Checking the null case
        vm.expectRevert(EnumerableALMMap.EnumerableALMMap__almNotFound.selector);
        (ALMStatus status, ALMPosition memory almPosition) = harness.getALM(address(uint160(3)));

        // Checking the active case
        (status, almPosition) = harness.getALM(address(uint160(1)));
        assert(status == ALMStatus.ACTIVE);
        assertEq(almPosition.slot0.almAddress, address(1));

        (status, almPosition) = harness.getALM(address(uint160(2)));
        assert(status == ALMStatus.ACTIVE);
        assertEq(almPosition.slot0.almAddress, address(2));

        // Checking the remove case
        harness.remove(address(uint160(1)));
        (status, almPosition) = harness.getALM(address(uint160(1)));
        assert(status == ALMStatus.REMOVED);
        assertEq(almPosition.slot0.almAddress, address(1));
    }

    function test_hardcodedAdd() public {
        assertEq(harness.length(), 0);
        assertEq(harness.values().length, 0);
        assertEq(harness.getNumBaseALMs(), 0);

        // Add a Base ALM
        harness.add(ALMPosition(Slot0(false, true, true, 0, address(uint160(1))), 0, 0, 0, 1));
        assertEq(harness.length(), 1);
        assertEq(harness.values().length, 1);
        assertEq(harness.values()[0].slot0.almAddress, address(uint160(1)));
        assertEq(harness.getNumBaseALMs(), 1);

        // Add a Base ALM - Revert because it cannot have a Meta ALM fee share
        vm.expectRevert(EnumerableALMMap.EnumerableALMMap__baseALMHasPositiveFeeShare.selector);
        harness.add(ALMPosition(Slot0(false, true, true, 1, address(uint160(2))), 0, 0, 0, 1));

        // Add a Base ALM - Revert because zero address is invalid
        vm.expectRevert(EnumerableALMMap.EnumerableALMMap__invalidALMAddress.selector);
        harness.add(ALMPosition(Slot0(false, true, true, 0, address(uint160(0))), 0, 0, 0, 1));

        // Add a Meta ALM
        harness.add(ALMPosition(Slot0(true, true, false, 1, address(uint160(2))), 0, 0, 0, 2));
        assertEq(harness.length(), 2);
        assertEq(harness.values().length, 2);
        assertEq(harness.values()[1].slot0.almAddress, address(uint160(2)));
        assertEq(harness.getNumBaseALMs(), 1);

        // Add a Meta ALM - Revert because Meta ALMs cannot share quotes
        vm.expectRevert(EnumerableALMMap.EnumerableALMMap__metaALMCannotShareQuotes.selector);
        harness.add(ALMPosition(Slot0(true, true, true, 1, address(uint160(3))), 0, 0, 0, 2));

        // Add a Meta ALM - Revert because of excessive Meta ALM fee share
        vm.expectRevert(EnumerableALMMap.EnumerableALMMap__highMetaALMFeeShare.selector);
        harness.add(ALMPosition(Slot0(true, true, true, 5001, address(uint160(3))), 0, 0, 0, 2));

        // Add a Base ALM
        harness.add(ALMPosition(Slot0(false, true, true, 0, address(uint160(3))), 0, 0, 0, 3));
        assertEq(harness.length(), 3);
        assertEq(harness.values().length, 3);
        assertEq(harness.values()[1].slot0.almAddress, address(uint160(3)));
        assertEq(harness.values()[2].slot0.almAddress, address(uint160(2)));
        assertEq(harness.getNumBaseALMs(), 2);

        // Remove a Base ALM
        (ALMStatus status, ALMPosition memory alm) = harness.getALM(address(uint160(3)));
        harness.remove(address(uint160(3)));
        assertEq(harness.length(), 2);
        assertEq(harness.values().length, 2);
        assertEq(harness.values()[0].slot0.almAddress, address(uint160(1)));
        assertEq(harness.values()[1].slot0.almAddress, address(uint160(2)));
        assertEq(harness.getNumBaseALMs(), 1);
        (status, alm) = harness.getALM(address(uint160(3)));
        assert(status == ALMStatus.REMOVED);
        assertEq(alm.slot0.almAddress, address(uint160(3)));

        // Remove a Meta ALM
        harness.remove(address(uint160(2)));
        assertEq(harness.length(), 1);
        assertEq(harness.values().length, 1);
        assertEq(harness.values()[0].slot0.almAddress, address(uint160(1)));
        assertEq(harness.getNumBaseALMs(), 1);
        (status, alm) = harness.getALM(address(uint160(2)));
        assert(status == ALMStatus.REMOVED);
        assertEq(alm.slot0.almAddress, address(uint160(2)));
    }

    function test_getSlot0() public {
        harness.add(ALMPosition(Slot0(false, true, true, 0, address(uint160(1))), 0, 0, 0, 1));
        vm.expectRevert(EnumerableALMMap.EnumerableALMMap__almNotFound.selector);
        harness.getSlot0(1);

        Slot0 memory slot0 = harness.getSlot0(0);
        assertEq(slot0.almAddress, address(uint160(1)));

        harness.remove(address(uint160(1)));
        vm.expectRevert(EnumerableALMMap.EnumerableALMMap__almNotFound.selector);
        harness.getSlot0(0);
    }

    function test_updateReserves() public {
        ALMReserves memory reserves = ALMReserves(30, 25);
        harness.add(ALMPosition(Slot0(false, true, true, 0, address(uint160(1))), 0, 0, 0, 0));
        // Revert Case
        vm.expectRevert(EnumerableALMMap.EnumerableALMMap__almNotFound.selector);
        harness.updateReservesPostSwap(true, address(uint160(2)), reserves, 5);

        // Correct Case
        (, ALMPosition memory position) = harness.getALM(address(uint160(1)));
        harness.updateReservesPostSwap(true, address(uint160(1)), reserves, 5);
        (, position) = harness.getALM(address(uint160(1)));

        assertEq(position.reserve0, 30 + 5); // add fee as well
        assertEq(position.reserve1, 25);
        assertEq(position.feeCumulative0, 5);
        assertEq(position.feeCumulative1, 0);

        // reserves should be same even if alm is removed

        harness.remove(address(uint160(1)));

        ALMReserves memory almReserves = harness.getALMReserves(true, address(uint160(1)));

        assertEq(almReserves.tokenInReserves, 30 + 5);
        assertEq(almReserves.tokenOutReserves, 25);

        almReserves = harness.getALMReserves(false, address(uint160(1)));

        assertEq(almReserves.tokenInReserves, 25);
        assertEq(almReserves.tokenOutReserves, 30 + 5);
    }

    /************************************************
     *  Internal Functions
     ***********************************************/

    function _prepareSet(uint256 numBaseALM, uint256 numMetaALM) internal {
        for (uint256 i; i < numMetaALM; i++) {
            harness.add(ALMPosition(Slot0(true, true, false, 0, address(uint160(1 + i + numBaseALM))), 0, 0, 0, i));
        }

        assertEq(harness.getNumBaseALMs(), 0);
        for (uint256 i; i < numBaseALM; i++) {
            harness.add(ALMPosition(Slot0(false, true, true, 0, address(uint160(1 + i))), 0, 0, 0, i));
        }
        assertEq(harness.getNumBaseALMs(), numBaseALM);

        assertEq(numBaseALM + numMetaALM, harness.length());
    }
}
