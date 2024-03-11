// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { ALMReserves } from '../ALM/structs/UniversalALMStructs.sol';
import { ALMPosition, ALMStatus, Slot0 } from '../pools/structs/UniversalPoolStructs.sol';

/**
    @title Enumerable Map for ALMPosition struct.
    @notice Library for managing all whitelisted and removed ALMs in a pool.

    The data structure is similar to Open Zeppelin Enumerable Set:
    https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/structs/EnumerableSet.sol

    An ALMSet has the following properties - 
        - Elements are added, and  checked for existence in constant time (O(1)).
        - Elements are removed in O(n) time, and all elements to the right of the removed entity
          are shifted by one position to the left in the array.
        - Elements are enumerated in O(n). Ordering is maintained in all cases.
        - Elements are separated into 2 subcategories - Base ALM, Meta ALM. Indicated by the 'isMetaALM' flag.
        - 'add' and 'remove' functions ensure that all base ALMs are always placed before all meta ALMs
        - '_metaALMPointer' indicates the first index of a Meta ALM
           it can also be read as the total number of base ALMs in the Enumerable Set.
**/
library EnumerableALMMap {
    /************************************************
     *  CONSTANTS
     ***********************************************/

    /**
        @notice Maximum ALMs allowed in a single pool.
     */
    // solhint-disable-next-line private-vars-leading-underscore
    uint256 private constant MAX_ALMS_IN_POOL = 256;

    /**
        @notice Maximum fee share Meta ALMs can pay to base ALMs.
     */
    // solhint-disable-next-line private-vars-leading-underscore
    uint256 private constant MAX_META_ALM_FEE_SHARE = 5000;

    /************************************************
     *  EVENTS
     ***********************************************/

    event ALMAdded(address alm);
    event ALMRemoved(address alm);
    event MetaALMFeeShareSet(address indexed almAddress, uint256 newFeeShare);

    /************************************************
     *  CUSTOM ERRORS
     ***********************************************/

    error EnumerableALMMap__addALMPosition();
    error EnumerableALMMap__almNotFound();
    error EnumerableALMMap__baseALMHasPositiveFeeShare();
    error EnumerableALMMap__highMetaALMFeeShare();
    error EnumerableALMMap__invalidALMAddress();
    error EnumerableALMMap__metaALMCannotShareQuotes();
    error EnumerableALMMap__removeALMPosition();
    error EnumerableALMMap__setMetaALMFeeShare_inactiveALM();
    error EnumerableALMMap__setMetaALMFeeShare_notMetaALM();
    error EnumerableALMMap__updateReservesPostSwap_inactiveALM();

    /************************************************
     *  STRUCTS
     ***********************************************/

    /**
        @notice Struct which contains the Enumerable ALM Map Data structure.
        @dev _metaALMPointer Points to the real index of the first meta ALM in the array.
        @dev _activeALMs Stores the active ALMPosition objects in an array.
        @dev _removedALMs Stores the ALMPosition objects which have been removed from the pool.
        @dev _indexes Maps the address of active ALMs with the index of their position in the array.
        @dev _removedALMIndexes Maps the address of removed ALMs with the index of their position in the array.
     */
    struct ALMSet {
        uint256 _metaALMPointer;
        ALMPosition[] _activeALMs;
        ALMPosition[] _removedALMs;
        mapping(address => uint256) _indexes;
        mapping(address => uint256) _removedALMIndexes;
    }

    /************************************************
     *  FUNCTIONS
     ***********************************************/

    /**
        @notice Adds ALM to the data structure.
        @dev If ALM is of type 'Base ALM', it is stored at index i in the _activeALMs array,
             and _indexes[almAddress] = i+1.
             This is done to check for existence in O(1) time, by checking _indexes[almAddress] == 0.
             If ALM is of type 'Meta ALM', it is replaced with the meta ALM at position _metaALMPointer
             and _indexes[almAddress] = _metaALMPointer + 1.
             The Meta ALM is then placed at the end of the array. This is done to ensure that all basic ALMs
             are added before all Meta ALMs.
        @param _alm takes ALMPosition struct as input.
    */
    function add(ALMSet storage _set, ALMPosition memory _alm) external {
        uint256 almLength = _set._activeALMs.length;

        if (_alm.slot0.almAddress == address(0)) {
            revert EnumerableALMMap__invalidALMAddress();
        }

        // Cannot Add ALM in a pool, if already MAX_ALMS_IN_POOL are present
        if (almLength == MAX_ALMS_IN_POOL) {
            revert EnumerableALMMap__addALMPosition();
        }

        // Excessive Meta ALM fee share
        if (_alm.slot0.isMetaALM && _alm.slot0.metaALMFeeShare > MAX_META_ALM_FEE_SHARE) {
            revert EnumerableALMMap__highMetaALMFeeShare();
        }

        // Meta ALMs cannot share quotes
        if (_alm.slot0.isMetaALM && _alm.slot0.shareQuotes) {
            revert EnumerableALMMap__metaALMCannotShareQuotes();
        }

        // Base ALMs cannot have a positive Meta ALM fee share
        if (!_alm.slot0.isMetaALM && _alm.slot0.metaALMFeeShare != 0) {
            revert EnumerableALMMap__baseALMHasPositiveFeeShare();
        }

        // Cannot add ALM if it already exists in either active or removed ALMs
        if (_set._indexes[_alm.slot0.almAddress] == 0 && _set._removedALMIndexes[_alm.slot0.almAddress] == 0) {
            // If ALM is not a meta ALM, swap it with first meta ALM
            if (!_alm.slot0.isMetaALM) {
                uint256 metaALMPointer = _set._metaALMPointer;

                if (metaALMPointer == almLength) {
                    // No Meta ALMs in the set, directly push the Base ALM to the end of the array
                    _set._activeALMs.push(_alm);
                } else {
                    // Push the first Meta ALM, to the end of the array
                    _set._activeALMs.push(_set._activeALMs[metaALMPointer]);
                    _set._indexes[_set._activeALMs[metaALMPointer].slot0.almAddress] = almLength + 1;

                    // Replace the _metaALMPointer index with the new Base ALM
                    _set._activeALMs[metaALMPointer] = _alm;
                }

                _set._indexes[_alm.slot0.almAddress] = metaALMPointer + 1;

                // Each time base ALM is added, meta ALM index increases
                ++_set._metaALMPointer;
            } else {
                _set._activeALMs.push(_alm);
                _set._indexes[_alm.slot0.almAddress] = almLength + 1;
            }

            emit ALMAdded(_alm.slot0.almAddress);
        } else {
            revert EnumerableALMMap__addALMPosition();
        }
    }

    /**
        @notice Remove ALM from the data structure.
        @notice This is a O(n) operation, but it maintains the ordering of the array.
                It also ensures that all Base ALMs remain before the Meta ALMs in the array.
        @dev If ALM is stored at index i in the _activeALMs array, then all elements with index > i,
             are shifted one position to the left.
        @param _almAddress Address of the ALM to remove.
    */
    function remove(ALMSet storage _set, address _almAddress) external {
        uint256 value = _set._indexes[_almAddress];

        if (value != 0) {
            uint256 toDeleteIndex = value - 1;
            uint256 len = _set._activeALMs.length - 1;

            // ALMs can never be removed from the removedALMs array
            _set._removedALMs.push(_set._activeALMs[toDeleteIndex]);
            _set._removedALMIndexes[_almAddress] = _set._removedALMs.length;

            // If a Base ALM is removed, then _metaALMPointer -= 1
            if (!_set._activeALMs[toDeleteIndex].slot0.isMetaALM) {
                --_set._metaALMPointer;
            }

            // Shift all ALMs starting from toDeleteIndex + 1, one place to the left
            for (uint256 i = toDeleteIndex; i < len; ) {
                ALMPosition memory nextValue = _set._activeALMs[i + 1];
                _set._activeALMs[i] = nextValue;
                _set._indexes[nextValue.slot0.almAddress] = i + 1;

                unchecked {
                    ++i;
                }
            }

            // Delete the last element, and delete the almAddress from index mapping
            _set._activeALMs.pop();
            delete _set._indexes[_almAddress];

            emit ALMRemoved(_almAddress);
        } else {
            revert EnumerableALMMap__removeALMPosition();
        }
    }

    /**
        @notice Sets the value of the ALMPosition's 'metaALMFeeShare'. Only relevant if ALM is a Meta ALM.
        @param almAddress Address of the ALM.
        @param newFeeShare New value of the fee share.
    */
    function setMetaALMFeeShare(ALMSet storage set, address almAddress, uint64 newFeeShare) internal {
        if (newFeeShare > MAX_META_ALM_FEE_SHARE) {
            revert EnumerableALMMap__highMetaALMFeeShare();
        }

        (ALMStatus status, uint256 index) = _getRealIndex(set, almAddress);

        // Should never occur
        if (status != ALMStatus.ACTIVE) revert EnumerableALMMap__setMetaALMFeeShare_inactiveALM();

        if (!set._activeALMs[index].slot0.isMetaALM) revert EnumerableALMMap__setMetaALMFeeShare_notMetaALM();

        set._activeALMs[index].slot0.metaALMFeeShare = newFeeShare;

        emit MetaALMFeeShareSet(almAddress, newFeeShare);
    }

    /**
        @notice Updates the reserves and fees for an ALM Position post swap.
        @param isZeroToOne Direction of the swap.
        @param almAddress Address of the ALM.
        @param almReserves Updated reserves of the ALM.
        @param fee Total fee received by ALM (in tokenIn).
    */
    function updateReservesPostSwap(
        ALMSet storage set,
        bool isZeroToOne,
        address almAddress,
        ALMReserves memory almReserves,
        uint256 fee
    ) internal {
        (ALMStatus status, uint256 index) = _getRealIndex(set, almAddress);
        // Should never occur
        if (status != ALMStatus.ACTIVE) revert EnumerableALMMap__updateReservesPostSwap_inactiveALM();

        if (isZeroToOne) {
            set._activeALMs[index].reserve0 = almReserves.tokenInReserves + fee;
            set._activeALMs[index].reserve1 = almReserves.tokenOutReserves;
            set._activeALMs[index].feeCumulative0 += fee;
        } else {
            set._activeALMs[index].reserve1 = almReserves.tokenInReserves + fee;
            set._activeALMs[index].reserve0 = almReserves.tokenOutReserves;
            set._activeALMs[index].feeCumulative1 += fee;
        }
    }

    /**
        @notice Returns length of the ALM Map.
    */
    function length(ALMSet storage set) internal view returns (uint256) {
        return set._activeALMs.length;
    }

    /**
        @notice Returns the array of all ALMPosition objects in the correct order.
    */
    function values(ALMSet storage set) internal view returns (ALMPosition[] memory) {
        return set._activeALMs;
    }

    /**
        @notice Returns the value of ALMPosition for a particular address.
        @param almAddress Address of the ALM.
        @return status Status of the ALM (ACTIVE or REMOVED).
        @return almPosition ALM position struct as a storage reference.
    */
    function getALM(
        ALMSet storage set,
        address almAddress
    ) internal view returns (ALMStatus status, ALMPosition storage almPosition) {
        uint256 index;
        (status, index) = _getRealIndex(set, almAddress);
        almPosition = status == ALMStatus.ACTIVE ? set._activeALMs[index] : set._removedALMs[index];
    }

    /**
        @notice Returns the 'Slot0' struct for the ALM Position, at the given index.
        @param index Index of the ALM in the set.
    */
    function getSlot0(ALMSet storage set, uint256 index) internal view returns (Slot0 memory) {
        if (index >= set._activeALMs.length) {
            revert EnumerableALMMap__almNotFound();
        }

        return set._activeALMs[index].slot0;
    }

    /**
        @notice Returns the number of base ALMs in the set, which is the same as the '_metaALMPointer'.
    */
    function getNumBaseALMs(ALMSet storage set) internal view returns (uint256) {
        return set._metaALMPointer;
    }

    /**
        @notice Returns the reserves of the ALM Position in order (tokenIn, tokenOut).
        @param isZeroToOne Direction of the swap.
        @param almAddress Address of the ALM.
        @dev Assumes that almAddress is present in either active or removed array.
        @return reserves Struct containing (tokenIn, tokenOut) reserves.
    */
    function getALMReserves(
        ALMSet storage set,
        bool isZeroToOne,
        address almAddress
    ) internal view returns (ALMReserves memory reserves) {
        (ALMStatus status, uint256 index) = _getRealIndex(set, almAddress);

        if (status == ALMStatus.ACTIVE) {
            if (isZeroToOne) {
                reserves = ALMReserves(set._activeALMs[index].reserve0, set._activeALMs[index].reserve1);
            } else {
                reserves = ALMReserves(set._activeALMs[index].reserve1, set._activeALMs[index].reserve0);
            }
        } else {
            if (isZeroToOne) {
                reserves = ALMReserves(set._removedALMs[index].reserve0, set._removedALMs[index].reserve1);
            } else {
                reserves = ALMReserves(set._removedALMs[index].reserve1, set._removedALMs[index].reserve0);
            }
        }
    }

    /**
        @notice Returns true if the ALM is in the active ALM array, false otherwise.
        @param almAddress Address of the ALM.
    */
    function isALMActive(ALMSet storage set, address almAddress) internal view returns (bool) {
        return set._indexes[almAddress] != 0;
    }

    /**
        @notice Returns the actual index of the ALM in the array.
        @param almAddress Address of the ALM.
        @return status Status of the ALM.
        @return index Index of the ALM in its respective array.
    */
    function _getRealIndex(ALMSet storage set, address almAddress) private view returns (ALMStatus, uint256) {
        uint256 index = set._indexes[almAddress];

        if (index != 0) {
            return (ALMStatus.ACTIVE, index - 1);
        }

        index = set._removedALMIndexes[almAddress];

        if (index == 0) {
            revert EnumerableALMMap__almNotFound();
        }

        return (ALMStatus.REMOVED, index - 1);
    }
}
