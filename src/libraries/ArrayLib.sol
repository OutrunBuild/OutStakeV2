// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

library ArrayLib {
    /// @notice Returns the sum of all input values.
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
     * @dev Assumes each input array has no duplicate elements internally.
     * @param a First address array.
     * @param b Second address array.
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
    function contains(address[] memory array, address element) internal pure returns (bool) {
        return find(array, element) != type(uint256).max;
    }

    /// @notice Returns whether `array` contains `element`.
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
    function create(address a) internal pure returns (address[] memory res) {
        res = new address[](1);
        res[0] = a;
    }

    /// @notice Creates an address array with two elements.
    function create(address a, address b) internal pure returns (address[] memory res) {
        res = new address[](2);
        res[0] = a;
        res[1] = b;
    }

    /// @notice Creates an address array with three elements.
    function create(address a, address b, address c) internal pure returns (address[] memory res) {
        res = new address[](3);
        res[0] = a;
        res[1] = b;
        res[2] = c;
    }

    /// @notice Creates an address array with four elements.
    function create(address a, address b, address c, address d) internal pure returns (address[] memory res) {
        res = new address[](4);
        res[0] = a;
        res[1] = b;
        res[2] = c;
        res[3] = d;
    }

    /// @notice Creates an address array with five elements.
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
    function create(uint256 a) internal pure returns (uint256[] memory res) {
        res = new uint256[](1);
        res[0] = a;
    }
}
