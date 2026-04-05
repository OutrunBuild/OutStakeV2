// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {OutrunERC20} from "../../src/assets/base/OutrunERC20.sol";
import {IAToken} from "../../src/integrations/aave/interfaces/IAToken.sol";
import {AaveAdapterLib} from "../../src/libraries/AaveAdapterLib.sol";
import {IStandardizedYield} from "../../src/yield/interfaces/IStandardizedYield.sol";
import {OutrunAaveV3SY} from "../../src/yield/adapters/aave/OutrunAaveV3SY.sol";

contract MockAaveUnderlyingToken is OutrunERC20 {
    constructor() OutrunERC20("Mock Underlying", "mUNDER", 18) {}
}

contract MockAToken is OutrunERC20, IAToken {
    address internal immutable underlyingAsset;

    constructor(address underlying_) OutrunERC20("Mock Aave Token", "maTOKEN", 18) {
        underlyingAsset = underlying_;
    }

    // solhint-disable-next-line func-name-mixedcase
    function UNDERLYING_ASSET_ADDRESS() external view returns (address) {
        return underlyingAsset;
    }

    function scaledBalanceOf(address user) external view returns (uint256) {
        return balanceOf(user);
    }

    function getScaledUserBalanceAndSupply(address user) external view returns (uint256, uint256) {
        return (balanceOf(user), totalSupply);
    }

    function scaledTotalSupply() external view returns (uint256) {
        return totalSupply;
    }

    function getPreviousIndex(address) external pure returns (uint256) {
        return 0;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}

contract MockAavePool {
    uint256 internal immutable normalizedIncome;

    constructor(uint256 normalizedIncome_) {
        normalizedIncome = normalizedIncome_;
    }

    function supply(address, uint256, address, uint16) external pure {
        return;
    }

    function withdraw(address, uint256 amount, address) external pure returns (uint256) {
        return amount;
    }

    function getReserveNormalizedIncome(address) external view returns (uint256) {
        return normalizedIncome;
    }
}

contract OutrunAaveV3SYHarness is OutrunAaveV3SY {
    constructor(address aToken_, address aavePool_, address owner_)
        OutrunAaveV3SY("SY Aave", "SYA", aToken_, aavePool_, owner_)
    {}

    function mintShares(address receiver, uint256 amount) external {
        _mint(receiver, amount);
    }
}

contract OutrunAaveV3SYTest is Test {
    address internal constant OWNER = address(0xA11CE);
    address internal constant USER = address(0xB0B);
    address internal constant RECEIVER = address(0xCAFE);

    uint256 internal constant NORMALIZED_INCOME = 1e27 + 123_456_789;
    uint256 internal constant SHARES_TO_REDEEM = 10 ether;

    MockAaveUnderlyingToken internal underlying;
    MockAToken internal aToken;
    MockAavePool internal aavePool;
    OutrunAaveV3SYHarness internal sy;

    function setUp() external {
        underlying = new MockAaveUnderlyingToken();
        aToken = new MockAToken(address(underlying));
        aavePool = new MockAavePool(NORMALIZED_INCOME);
        sy = new OutrunAaveV3SYHarness(address(aToken), address(aavePool), OWNER);

        sy.mintShares(USER, SHARES_TO_REDEEM);
        aToken.mint(address(sy), AaveAdapterLib.calcSharesToAssetDown(SHARES_TO_REDEEM, NORMALIZED_INCOME));
    }

    function testPreviewRedeemMatchesRedeemPathAtFullNormalizedIncomePrecision() external {
        uint256 expectedAssetsOut = AaveAdapterLib.calcSharesToAssetDown(SHARES_TO_REDEEM, NORMALIZED_INCOME);

        uint256 previewAssetsOut = sy.previewRedeem(address(aToken), SHARES_TO_REDEEM);

        vm.prank(USER);
        uint256 redeemedAssetsOut = sy.redeem(RECEIVER, SHARES_TO_REDEEM, address(aToken), 0, false);

        assertEq(previewAssetsOut, expectedAssetsOut);
        assertEq(redeemedAssetsOut, expectedAssetsOut);
        assertEq(previewAssetsOut, redeemedAssetsOut);
        assertEq(aToken.balanceOf(RECEIVER), expectedAssetsOut);
    }

    function testDepositUnderlyingRevertsOnSlippage() external {
        uint256 depositAmount = 10 ether;
        uint256 expectedShares = AaveAdapterLib.calcSharesFromAssetUp(depositAmount, NORMALIZED_INCOME);
        deal(address(underlying), USER, depositAmount);

        uint256 slippageMinShares = expectedShares + 1;

        vm.startPrank(USER);
        underlying.approve(address(sy), depositAmount);
        vm.expectRevert(
            abi.encodeWithSelector(
                IStandardizedYield.SYInsufficientSharesOut.selector, expectedShares, slippageMinShares
            )
        );
        sy.deposit(RECEIVER, address(underlying), depositAmount, slippageMinShares);
        vm.stopPrank();
    }

    function testRedeemRevertsOnSlippage() external {
        uint256 expectedAssetsOut = AaveAdapterLib.calcSharesToAssetDown(SHARES_TO_REDEEM, NORMALIZED_INCOME);
        uint256 minTokenOut = expectedAssetsOut + 1;

        vm.prank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(IStandardizedYield.SYInsufficientTokenOut.selector, expectedAssetsOut, minTokenOut)
        );
        sy.redeem(RECEIVER, SHARES_TO_REDEEM, address(underlying), minTokenOut, false);
    }

    function testDepositZeroReverts() external {
        deal(address(underlying), USER, 1 ether);
        vm.startPrank(USER);
        underlying.approve(address(sy), 1 ether);
        vm.expectRevert(IStandardizedYield.SYZeroDeposit.selector);
        sy.deposit(RECEIVER, address(underlying), 0, 0);
        vm.stopPrank();
    }

    function testRedeemZeroReverts() external {
        vm.prank(USER);
        vm.expectRevert(IStandardizedYield.SYZeroRedeem.selector);
        sy.redeem(RECEIVER, 0, address(underlying), 0, false);
    }
}
