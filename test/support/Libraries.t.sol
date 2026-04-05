// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {WadRayMath} from "../../src/libraries/WadRayMath.sol";
import {ArrayLib} from "../../src/libraries/ArrayLib.sol";
import {SYUtils} from "../../src/libraries/SYUtils.sol";
import {ReentrancyGuard} from "../../src/libraries/ReentrancyGuard.sol";

// ============================================================================
// WadRayMath Tests
// ============================================================================

contract WadRayMathTest is Test {
    using WadRayMath for uint256;

    // Helper contract to test reverts through external calls
    WadRayMathHelper helper;

    function setUp() public {
        helper = new WadRayMathHelper();
    }

    function testWadMulReturnsCorrectResult() public {
        uint256 a = 2e18;
        uint256 b = 3e18;
        uint256 result = a.wadMul(b);
        assertEq(result, 6e18);
    }

    function testWadMulRoundsDownCorrectly() public {
        // 1 * 3e18 / 1e18 = 3 with HALF_WAD = 5e17, so 1*3e18 + 5e17 = 3.5e18, rounds to 3
        uint256 result = uint256(1).wadMul(3e18);
        assertEq(result, 3);
    }

    function testWadMulRevertsOnOverflow() public {
        vm.expectRevert();
        helper.wadMulOverflow(type(uint256).max, 2);
    }

    function testWadDivReturnsCorrectResult() public {
        uint256 a = 6e18;
        uint256 b = 3e18;
        uint256 result = a.wadDiv(b);
        assertEq(result, 2e18);
    }

    function testWadDivRevertsOnZeroDivisor() public {
        vm.expectRevert();
        helper.wadDivZero(1e18);
    }

    function testWadDivRevertsOnOverflow() public {
        // Large numerator / small divisor can overflow
        vm.expectRevert();
        helper.wadDivOverflow(type(uint256).max, 1);
    }

    function testRayMulReturnsCorrectResult() public {
        uint256 a = 2e27;
        uint256 b = 3e27;
        uint256 result = a.rayMul(b);
        assertEq(result, 6e27);
    }

    function testRayMulRoundsDownCorrectly() public {
        // Small value rounding: 1 * 3e27 + HALF_RAY = 3.5e27, rounds to 3
        uint256 result = uint256(1).rayMul(3e27);
        assertEq(result, 3);
    }

    function testRayMulRevertsOnOverflow() public {
        vm.expectRevert();
        helper.rayMulOverflow(type(uint256).max, 2);
    }

    function testRayDivReturnsCorrectResult() public {
        uint256 a = 6e27;
        uint256 b = 3e27;
        uint256 result = a.rayDiv(b);
        assertEq(result, 2e27);
    }

    function testRayDivRevertsOnZeroDivisor() public {
        vm.expectRevert();
        helper.rayDivZero(1e27);
    }

    function testRayToWadRoundsUp() public {
        // 1.5e27 + 5e8: quotient = 1.5e18, remainder = 5e8 >= 5e8, so rounds up
        uint256 result = WadRayMath.rayToWad(1.5e27 + 5e8);
        assertEq(result, 1.5e18 + 1);
    }

    function testRayToWadTruncates() public {
        // 1.5e27 + 4e8: quotient = 1.5e18, remainder = 4e8 < 5e8, so truncates
        uint256 result = WadRayMath.rayToWad(1.5e27 + 4e8);
        assertEq(result, 1.5e18);
    }

    function testWadToRayRevertsOnOverflow() public {
        // Very large wad that overflows when multiplied by WAD_RAY_RATIO
        vm.expectRevert();
        helper.wadToRayOverflow(type(uint256).max / 1e9 + 1);
    }
}

// Helper contract for testing WadRayMath reverts
contract WadRayMathHelper {
    using WadRayMath for uint256;

    function wadMulOverflow(uint256 a, uint256 b) external pure {
        a.wadMul(b);
    }

    function wadDivZero(uint256 a) external pure {
        a.wadDiv(0);
    }

    function wadDivOverflow(uint256 a, uint256 b) external pure {
        a.wadDiv(b);
    }

    function rayMulOverflow(uint256 a, uint256 b) external pure {
        a.rayMul(b);
    }

    function rayDivZero(uint256 a) external pure {
        a.rayDiv(0);
    }

    function wadToRayOverflow(uint256 a) external pure {
        WadRayMath.wadToRay(a);
    }
}

// ============================================================================
// ArrayLib Tests
// ============================================================================

contract ArrayLibTest is Test {
    using ArrayLib for uint256[];
    using ArrayLib for address[];
    using ArrayLib for bytes4[];

    address constant A = address(0x1);
    address constant B = address(0x2);
    address constant C = address(0x3);
    address constant D = address(0x4);
    address constant E = address(0x5);

    function testSumReturnsZeroForEmptyArray() public {
        uint256[] memory arr = new uint256[](0);
        uint256 result = arr.sum();
        assertEq(result, 0);
    }

    function testSumReturnsCorrectTotal() public {
        uint256[] memory arr = new uint256[](3);
        arr[0] = 1;
        arr[1] = 2;
        arr[2] = 3;
        uint256 result = arr.sum();
        assertEq(result, 6);
    }

    function testFindReturnsIndexWhenPresent() public {
        address[] memory arr = new address[](3);
        arr[0] = A;
        arr[1] = B;
        arr[2] = C;
        uint256 result = arr.find(B);
        assertEq(result, 1);
    }

    function testFindReturnsMaxUint256WhenAbsent() public {
        address[] memory arr = new address[](2);
        arr[0] = A;
        arr[1] = B;
        uint256 result = arr.find(C);
        assertEq(result, type(uint256).max);
    }

    function testAppendAddsToEnd() public {
        address[] memory inp = new address[](2);
        inp[0] = A;
        inp[1] = B;
        address[] memory out = inp.append(C);
        assertEq(out.length, 3);
        assertEq(out[0], A);
        assertEq(out[1], B);
        assertEq(out[2], C);
    }

    function testAppendHeadAddsToStart() public {
        address[] memory inp = new address[](2);
        inp[0] = A;
        inp[1] = B;
        address[] memory out = inp.appendHead(C);
        assertEq(out.length, 3);
        assertEq(out[0], C);
        assertEq(out[1], A);
        assertEq(out[2], B);
    }

    function testMergeDeduplicates() public {
        address[] memory a = new address[](2);
        a[0] = A;
        a[1] = B;
        address[] memory b = new address[](2);
        b[0] = B;
        b[1] = C;
        address[] memory out = a.merge(b);
        assertEq(out.length, 3);
        assertEq(out[0], A);
        assertEq(out[1], B);
        assertEq(out[2], C);
    }

    function testMergeFullyDisjoint() public {
        address[] memory a = new address[](1);
        a[0] = A;
        address[] memory b = new address[](1);
        b[0] = B;
        address[] memory out = a.merge(b);
        assertEq(out.length, 2);
        assertEq(out[0], A);
        assertEq(out[1], B);
    }

    function testMergeIdenticalArrays() public {
        address[] memory a = new address[](2);
        a[0] = A;
        a[1] = B;
        address[] memory b = new address[](2);
        b[0] = A;
        b[1] = B;
        address[] memory out = a.merge(b);
        assertEq(out.length, 2);
        assertEq(out[0], A);
        assertEq(out[1], B);
    }

    function testContainsAddressReturnsTrueForPresent() public {
        address[] memory arr = new address[](3);
        arr[0] = A;
        arr[1] = B;
        arr[2] = C;
        bool result = arr.contains(B);
        assertTrue(result);
    }

    function testContainsAddressReturnsFalseForAbsent() public {
        address[] memory arr = new address[](2);
        arr[0] = A;
        arr[1] = B;
        bool result = arr.contains(C);
        assertFalse(result);
    }

    function testContainsBytes4ReturnsTrueForPresent() public {
        bytes4[] memory arr = new bytes4[](3);
        arr[0] = bytes4(0x11111111);
        arr[1] = bytes4(0x22222222);
        arr[2] = bytes4(0x33333333);
        bool result = arr.contains(bytes4(0x22222222));
        assertTrue(result);
    }

    function testContainsBytes4ReturnsFalseForAbsent() public {
        bytes4[] memory arr = new bytes4[](2);
        arr[0] = bytes4(0x11111111);
        arr[1] = bytes4(0x22222222);
        bool result = arr.contains(bytes4(0x33333333));
        assertFalse(result);
    }

    function testCreateVariableCount() public {
        address[] memory result1 = ArrayLib.create(A);
        assertEq(result1.length, 1);
        assertEq(result1[0], A);

        address[] memory result2 = ArrayLib.create(A, B);
        assertEq(result2.length, 2);
        assertEq(result2[0], A);
        assertEq(result2[1], B);

        address[] memory result3 = ArrayLib.create(A, B, C);
        assertEq(result3.length, 3);
        assertEq(result3[0], A);
        assertEq(result3[1], B);
        assertEq(result3[2], C);

        address[] memory result4 = ArrayLib.create(A, B, C, D);
        assertEq(result4.length, 4);
        assertEq(result4[0], A);
        assertEq(result4[1], B);
        assertEq(result4[2], C);
        assertEq(result4[3], D);

        address[] memory result5 = ArrayLib.create(A, B, C, D, E);
        assertEq(result5.length, 5);
        assertEq(result5[0], A);
        assertEq(result5[1], B);
        assertEq(result5[2], C);
        assertEq(result5[3], D);
        assertEq(result5[4], E);
    }

    function testCreateWithUint256() public {
        uint256[] memory result = ArrayLib.create(uint256(42));
        assertEq(result.length, 1);
        assertEq(result[0], 42);
    }
}

// ============================================================================
// SYUtils Tests
// ============================================================================

contract SYUtilsTest is Test {
    using SYUtils for uint256;

    function testSyToAssetReturnsCorrectValue() public {
        // With rate 1:1 (1e18), 1e18 SY -> 100 asset
        uint256 exchangeRate = 1e18;
        uint256 syAmount = 100;
        uint256 result = SYUtils.syToAsset(exchangeRate, syAmount);
        assertEq(result, 100);
    }

    function testSyToAssetWithRate2x() public {
        // With rate 2e18, 2e18 SY -> 400 asset
        uint256 exchangeRate = 2e18;
        uint256 syAmount = 200;
        uint256 result = SYUtils.syToAsset(exchangeRate, syAmount);
        assertEq(result, 400);
    }

    function testSyToAssetUpRoundsUp() public {
        // For small values, syToAssetUp >= syToAsset
        uint256 exchangeRate = 3;
        uint256 syAmount = 1;
        uint256 down = SYUtils.syToAsset(exchangeRate, syAmount);
        uint256 up = SYUtils.syToAssetUp(exchangeRate, syAmount);
        assertGe(up, down);
    }

    function testAssetToSyReturnsCorrectValue() public {
        // With rate 1:1 (1e18), 100 asset -> 100 SY
        uint256 exchangeRate = 1e18;
        uint256 assetAmount = 100;
        uint256 result = SYUtils.assetToSy(exchangeRate, assetAmount);
        assertEq(result, 100);
    }

    function testAssetToSyWithRate2x() public {
        // With rate 2e18, 200 asset -> 100 SY
        uint256 exchangeRate = 2e18;
        uint256 assetAmount = 200;
        uint256 result = SYUtils.assetToSy(exchangeRate, assetAmount);
        assertEq(result, 100);
    }

    function testAssetToSyUpRoundsUp() public {
        // For small values, assetToSyUp >= assetToSy
        uint256 exchangeRate = 3;
        uint256 assetAmount = 1;
        uint256 down = SYUtils.assetToSy(exchangeRate, assetAmount);
        uint256 up = SYUtils.assetToSyUp(exchangeRate, assetAmount);
        assertGe(up, down);
    }

    function testSyToAssetUpAlwaysGreaterOrEqualToSyToAsset() public {
        // For any rate, syToAssetUp >= syToAsset
        uint256 exchangeRate = 1e18 + 1; // Non-trivial rate
        uint256 syAmount = 1e18 - 1;
        uint256 down = SYUtils.syToAsset(exchangeRate, syAmount);
        uint256 up = SYUtils.syToAssetUp(exchangeRate, syAmount);
        assertGe(up, down);
    }

    function testAssetToSyUpAlwaysGreaterOrEqualToAssetToSy() public {
        // For any rate, assetToSyUp >= assetToSy
        uint256 exchangeRate = 1e18 + 1; // Non-trivial rate
        uint256 assetAmount = 1e18 - 1;
        uint256 down = SYUtils.assetToSy(exchangeRate, assetAmount);
        uint256 up = SYUtils.assetToSyUp(exchangeRate, assetAmount);
        assertGe(up, down);
    }

    function testRoundTripIdentity() public {
        // syToAsset(rate, assetToSy(rate, x)) == x for exact values
        uint256 exchangeRate = 1e18;
        uint256 assetAmount = 1e18;
        uint256 syAmount = SYUtils.assetToSy(exchangeRate, assetAmount);
        uint256 backToAsset = SYUtils.syToAsset(exchangeRate, syAmount);
        assertEq(backToAsset, assetAmount);
    }
}

// ============================================================================
// ReentrancyGuard Tests
// ============================================================================

contract MockGuarded is ReentrancyGuard {
    function guardedAction() external nonReentrant returns (uint256) {
        return 42;
    }

    function tryReenter() external nonReentrant {
        this.guardedAction(); // should revert
    }
}

contract ReentrancyGuardTest is Test {
    MockGuarded guarded;

    function setUp() public {
        guarded = new MockGuarded();
    }

    function testNonReentrantAllowsFirstCall() public {
        uint256 result = guarded.guardedAction();
        assertEq(result, 42);
    }

    function testNonReentrantRevertsOnReentry() public {
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        guarded.tryReenter();
    }

    function testGuardResetsAfterFunctionReturns() public {
        // First call
        uint256 result1 = guarded.guardedAction();
        assertEq(result1, 42);
        // Second call should also succeed (guard properly resets)
        uint256 result2 = guarded.guardedAction();
        assertEq(result2, 42);
    }
}
