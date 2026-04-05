// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IStandardizedYield} from "../../src/yield/interfaces/IStandardizedYield.sol";

import {OutrunERC20} from "../../src/assets/base/OutrunERC20.sol";
import {OutrunAaveV3SY} from "../../src/yield/adapters/aave/OutrunAaveV3SY.sol";
import {AaveAdapterLib} from "../../src/libraries/AaveAdapterLib.sol";
import {IAToken} from "../../src/integrations/aave/interfaces/IAToken.sol";

// ---- Aave adapter mocks ----
contract FuzzMockUnderlying is OutrunERC20 {
    constructor() OutrunERC20("Underlying", "UND", 18) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// FuzzMockAToken implements IAToken but does NOT implement IERC20 directly.
// We inherit from OutrunERC20 for base ERC20 behavior and manually satisfy IAToken interface.
contract FuzzMockAToken is OutrunERC20, IAToken {
    address public immutable underlyingAsset;

    constructor(address underlying_) OutrunERC20("aToken", "aT", 18) {
        underlyingAsset = underlying_;
    }

    function UNDERLYING_ASSET_ADDRESS() external view returns (address) {
        return underlyingAsset;
    }

    function scaledBalanceOf(address) external pure returns (uint256) {
        return 0;
    }

    function getScaledUserBalanceAndSupply(address) external pure returns (uint256, uint256) {
        return (0, 0);
    }

    function scaledTotalSupply() external pure returns (uint256) {
        return 0;
    }

    function getPreviousIndex(address) external pure returns (uint256) {
        return 0;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract FuzzMockAavePool {
    uint256 public normalizedIncome;

    constructor(uint256 _normalizedIncome) {
        normalizedIncome = _normalizedIncome;
    }
    function supply(address, uint256, address, uint16) external pure {}

    function withdraw(address, uint256 amount, address) external pure returns (uint256) {
        return amount;
    }

    function getReserveNormalizedIncome(address) external view returns (uint256) {
        return normalizedIncome;
    }

    function setNormalizedIncome(uint256 _ni) external {
        normalizedIncome = _ni;
    }
}

// Test harness that exposes internal minting for fuzz setup
contract FuzzAaveSYHarness is OutrunAaveV3SY {
    constructor(address aToken_, address aavePool_, address owner_)
        OutrunAaveV3SY("Fuzz SY Aave", "FSA", aToken_, aavePool_, owner_)
    {}

    function mintShares(address receiver, uint256 amount) external {
        _mint(receiver, amount);
    }
}

contract SYAdapterFuzz is Test {
    address internal constant OWNER = address(0xA11CE);

    FuzzMockUnderlying internal underlying;
    FuzzMockAToken internal aToken;
    FuzzMockAavePool internal aavePool;
    FuzzAaveSYHarness internal sy;

    uint256 internal constant MIN_DEPOSIT = 1;
    uint256 internal constant MIN_NI = 1e27;
    uint256 internal constant MAX_NI = 15e26;

    function setUp() external {
        underlying = new FuzzMockUnderlying();
        aToken = new FuzzMockAToken(address(underlying));
        aavePool = new FuzzMockAavePool(1e27);
        sy = new FuzzAaveSYHarness(address(aToken), address(aavePool), OWNER);
    }

    /**
     * @dev Fuzz the slippage boundary for Aave adapter deposits.
     *      Verifies that deposits succeed at exact expectedShares and revert when minShares is 1 wei too high.
     */
    function testFuzz_DepositSlippageBoundary(uint256 amount, uint256 normalizedIncome) external {
        amount = bound(amount, MIN_DEPOSIT, 10_000 ether);
        normalizedIncome = bound(normalizedIncome, MIN_NI, MAX_NI);
        aavePool.setNormalizedIncome(normalizedIncome);

        uint256 expectedShares = AaveAdapterLib.calcSharesFromAssetUp(amount, normalizedIncome);
        deal(address(underlying), address(this), amount);
        underlying.approve(address(sy), amount);

        uint256 sharesOut = sy.deposit(address(this), address(underlying), amount, expectedShares);
        assertEq(sharesOut, expectedShares, "shares should match expected at exact minShares");

        // Second deposit: fund again and verify slippage revert
        deal(address(underlying), address(this), amount);
        underlying.approve(address(sy), amount);
        vm.expectRevert(
            abi.encodeWithSelector(
                IStandardizedYield.SYInsufficientSharesOut.selector, expectedShares, expectedShares + 1
            )
        );
        sy.deposit(address(this), address(underlying), amount, expectedShares + 1);
    }

    /**
     * @dev Fuzz a deposit/redeem roundtrip where normalized income changes between deposit and redeem.
     *      Verifies that assetsOut matches the down-calculated amount at the new rate.
     */
    function testFuzz_ExchangeRateChangeRoundtrip(uint256 amount, uint256 niBefore, uint256 niAfter) external {
        amount = bound(amount, MIN_DEPOSIT, 1000 ether);
        niBefore = bound(niBefore, MIN_NI, MAX_NI);
        niAfter = bound(niAfter, MIN_NI, MAX_NI);
        vm.assume(niBefore != niAfter);

        aavePool.setNormalizedIncome(niBefore);
        uint256 sharesBefore = AaveAdapterLib.calcSharesFromAssetUp(amount, niBefore);
        deal(address(underlying), address(this), amount);
        underlying.approve(address(sy), amount);
        uint256 sharesOut = sy.deposit(address(this), address(underlying), amount, 0);
        assertEq(sharesOut, sharesBefore, "deposit shares should match calc at niBefore");

        // Change normalized income and redeem
        aavePool.setNormalizedIncome(niAfter);

        uint256 expectedAssetsOut = AaveAdapterLib.calcSharesToAssetDown(sharesOut, niAfter);
        aToken.mint(address(sy), expectedAssetsOut + 1); // fund SY with aToken for redemption
        uint256 assetsOut = sy.redeem(address(this), sharesOut, address(underlying), 0, false);
        assertEq(assetsOut, expectedAssetsOut, "assets out should match calc at niAfter");
    }

    /**
     * @dev Fuzz partial redeem: after depositing and partially redeeming,
     *      the remaining share balance should equal deposit minus redeem.
     *      Uses the underlying asset as redemption target for reliable liquidity.
     */
    function testFuzz_PartialRedeemLeavesCorrectBalance(uint256 depositAmount, uint256 redeemFraction) external {
        depositAmount = bound(depositAmount, 1000, 1000 ether); // Min to avoid truncation edge
        redeemFraction = bound(redeemFraction, 1, 90); // 1% to 90%

        deal(address(underlying), address(this), depositAmount);
        underlying.approve(address(sy), depositAmount);
        uint256 sharesOut = sy.deposit(address(this), address(underlying), depositAmount, 0);

        uint256 redeemAmount = (sharesOut * redeemFraction) / 100;
        // Fund the aToken pool with enough for withdrawal at the current normalized income
        uint256 ni = 1e27;
        aavePool.setNormalizedIncome(ni);
        uint256 needed = AaveAdapterLib.calcSharesToAssetDown(sharesOut, ni) + 2;
        aToken.mint(address(sy), needed);
        underlying.mint(address(aavePool), needed + 100); // fund pool for withdrawals

        uint256 tokens = sy.redeem(address(this), redeemAmount, address(underlying), 0, false);

        assertGt(tokens, 0, "partial redeem should return tokens");
        assertEq(
            sy.balanceOf(address(this)), sharesOut - redeemAmount, "remaining shares should equal deposit minus redeem"
        );
    }

    /**
     * @dev Fuzz deposit across the full valid amount range.
     */
    function testFuzz_DepositAmountBoundaries(uint256 amount) external {
        amount = bound(amount, MIN_DEPOSIT, 10_000 ether);
        deal(address(underlying), address(this), amount);
        underlying.approve(address(sy), amount);
        uint256 sharesOut = sy.deposit(address(this), address(underlying), amount, 0);
        assertEq(
            sharesOut,
            AaveAdapterLib.calcSharesFromAssetUp(amount, 1e27),
            "shares should match calcSharesFromAssetUp at NI=1e27"
        );
    }
}
