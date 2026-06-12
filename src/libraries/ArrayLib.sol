// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

library ArrayLib {
    /// @notice Returns the sum of all input values.
    /// @param input Array of uint256 values to sum.
    /// @return The total sum of all values in the array.
    function sum(uint256[] memory input) internal pure returns (uint256) {
        uint256 value = 0;
        uint256 length = input.length;
        for (uint256 i = 0; i < length;) {
            value += input[i];
            unchecked {
                ++i;
            }
        }
        return value;
    }

    /// @notice Returns the element index when found, otherwise returns `type(uint256).max`.
    /// @param array The address array to search.
    /// @param element The address to find.
    /// @return index The index of element in array, or type(uint256).max if not found.
    /// @dev Callers MUST check the returned index against type(uint256).max — this sentinel means "not found".
    function find(address[] memory array, address element) internal pure returns (uint256 index) {
        uint256 length = array.length;
        for (uint256 i = 0; i < length;) {
            if (array[i] == element) return i;
            unchecked {
                ++i;
            }
        }
        return type(uint256).max;
    }

    /// @notice Returns a copy of `inp` with `element` appended at the tail.
    /// @param inp The original address array.
    /// @param element The address to append.
    /// @return out A new array with element added at the end.
    function append(address[] memory inp, address element) internal pure returns (address[] memory out) {
        uint256 length = inp.length;
        out = new address[](length + 1);
        for (uint256 i = 0; i < length;) {
            out[i] = inp[i];
            unchecked {
                ++i;
            }
        }
        out[length] = element;
    }

    /// @notice Returns a copy of `inp` with `element` inserted at the head.
    /// @param inp The original address array.
    /// @param element The address to insert at position 0.
    /// @return out A new array with element at the head.
    function appendHead(address[] memory inp, address element) internal pure returns (address[] memory out) {
        uint256 length = inp.length;
        out = new address[](length + 1);
        out[0] = element;
        for (uint256 i = 0; i < length;) {
            out[i + 1] = inp[i];
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Merges two arrays, appending elements from `b` that are not already in `a`.
     * @dev Creates a new array containing all elements from `a` plus any elements from `b`
     * that are not already in `a`. Does not modify either input array.
     * Assumes each input array has no duplicate elements internally.
     * @param a First address array (all elements included in output).
     * @param b Second address array (only new elements are appended).
     * @return out Concatenation of `a` and addresses from `b` that are not in `a`.
     */
    function merge(address[] memory a, address[] memory b) internal pure returns (address[] memory out) {
        unchecked {
            uint256 countUnidenticalB = 0;
            uint256 bLength = b.length;
            bool[] memory isUnidentical = new bool[](bLength);
            for (uint256 i = 0; i < bLength; ++i) {
                if (!contains(a, b[i])) {
                    ++countUnidenticalB;
                    isUnidentical[i] = true;
                }
            }

            uint256 aLength = a.length;
            out = new address[](aLength + countUnidenticalB);
            for (uint256 i = 0; i < aLength; ++i) {
                out[i] = a[i];
            }
            uint256 id = aLength;
            for (uint256 i = 0; i < bLength; ++i) {
                if (isUnidentical[i]) {
                    out[id] = b[i];
                    ++id;
                }
            }
        }
    }

    /// @notice Returns whether `array` contains `element`.
    /// @param array The address array to search.
    /// @param element The address to find.
    /// @return True if element is found in array.
    function contains(address[] memory array, address element) internal pure returns (bool) {
        return find(array, element) != type(uint256).max;
    }

    /// @notice Returns whether `array` contains `element`.
    /// @param array The bytes4 array to search.
    /// @param element The bytes4 selector to find.
    /// @return True if element is found in array.
    function contains(bytes4[] memory array, bytes4 element) internal pure returns (bool) {
        uint256 length = array.length;
        for (uint256 i = 0; i < length;) {
            if (array[i] == element) return true;
            unchecked {
                ++i;
            }
        }
        return false;
    }

    /// @notice Creates an address array with one element.
    /// @param a The element.
    /// @return res A new array of length 1.
    function create(address a) internal pure returns (address[] memory res) {
        res = new address[](1);
        res[0] = a;
    }

    /// @notice Creates an address array with two elements.
    /// @param a First element.
    /// @param b Second element.
    /// @return res A new array of length 2.
    function create(address a, address b) internal pure returns (address[] memory res) {
        res = new address[](2);
        res[0] = a;
        res[1] = b;
    }

    /// @notice Creates an address array with three elements.
    /// @param a First element.
    /// @param b Second element.
    /// @param c Third element.
    /// @return res A new array of length 3.
    function create(address a, address b, address c) internal pure returns (address[] memory res) {
        res = new address[](3);
        res[0] = a;
        res[1] = b;
        res[2] = c;
    }

    /// @notice Creates an address array with four elements.
    /// @param a First element.
    /// @param b Second element.
    /// @param c Third element.
    /// @param d Fourth element.
    /// @return res A new array of length 4.
    function create(address a, address b, address c, address d) internal pure returns (address[] memory res) {
        res = new address[](4);
        res[0] = a;
        res[1] = b;
        res[2] = c;
        res[3] = d;
    }

    /// @notice Creates an address array with five elements.
    /// @param a First element.
    /// @param b Second element.
    /// @param c Third element.
    /// @param d Fourth element.
    /// @param e Fifth element.
    /// @return res A new array of length 5.
    function create(address a, address b, address c, address d, address e)
        internal
        pure
        returns (address[] memory res)
    {
        res = new address[](5);
        res[0] = a;
        res[1] = b;
        res[2] = c;
        res[3] = d;
        res[4] = e;
    }

    /// @notice Creates a uint256 array with one element.
    /// @param a The element.
    /// @return res A new array of length 1.
    function create(uint256 a) internal pure returns (uint256[] memory res) {
        res = new uint256[](1);
        res[0] = a;
    }
}
