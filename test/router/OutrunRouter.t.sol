// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {OutrunRouter} from "../../src/router/OutrunRouter.sol";
import {IOutrunRouter} from "../../src/router/interfaces/IOutrunRouter.sol";
import {OutrunStakingPosition} from "../../src/position/OutrunStakingPosition.sol";
import {IStandardizedYield} from "../../src/yield/interfaces/IStandardizedYield.sol";
import {IUniversalAssets} from "../../src/assets/interfaces/IUniversalAssets.sol";
import {OutrunERC20} from "../../src/assets/base/OutrunERC20.sol";

interface IOutrunRouterPrefundless {
    function mintSYFromToken(address SY, address tokenIn, address receiver, uint256 amountInput, uint256 minSyOut)
        external
        payable
        returns (uint256 amountInSYOut);

    function redeemSyToToken(address SY, address receiver, address tokenOut, uint256 amountInSY, uint256 minTokenOut)
        external
        returns (uint256 amountInTokenOut);
}

contract RouterMockSY is OutrunERC20, IStandardizedYield {
    error RouterDepositTransferFailed();

    address internal immutable underlying;
    uint256 internal rate;
    address internal lastDepositTokenIn;
    uint256 internal lastDepositAmount;
    uint256 internal lastDepositValue;

    constructor(address underlying_) OutrunERC20("Mock SY", "mSY", 18) {
        underlying = underlying_;
        rate = 1e18;
    }

    function setExchangeRate(uint256 newRate) external {
        rate = newRate;
    }

    function mintShares(address receiver, uint256 amount) external {
        _mint(receiver, amount);
    }

    function deposit(address receiver, address tokenIn, uint256 amountTokenToDeposit, uint256)
        external
        payable
        returns (uint256 amountSharesOut)
    {
        lastDepositTokenIn = tokenIn;
        lastDepositAmount = amountTokenToDeposit;
        lastDepositValue = msg.value;
        if (msg.value == 0) {
            if (!RouterMockERC20(underlying).transferFrom(msg.sender, address(this), amountTokenToDeposit)) {
                revert RouterDepositTransferFailed();
            }
        }
        amountSharesOut = amountTokenToDeposit;
        _mint(receiver, amountSharesOut);
    }

    function redeem(
        address receiver,
        uint256 amountSharesToRedeem,
        address tokenOut,
        uint256,
        bool burnFromInternalBalance
    ) external returns (uint256 amountTokenOut) {
        if (burnFromInternalBalance) {
            _burn(address(this), amountSharesToRedeem);
        } else {
            _burn(msg.sender, amountSharesToRedeem);
        }

        amountTokenOut = amountSharesToRedeem;
        if (tokenOut == address(this)) {
            _mint(receiver, amountTokenOut);
        } else {
            RouterMockERC20(tokenOut).mint(receiver, amountTokenOut);
        }
    }

    function exchangeRate() external view returns (uint256 res) {
        res = rate;
    }

    function yieldBearingToken() external view returns (address) {
        return underlying;
    }

    function getTokensIn() external view returns (address[] memory res) {
        res = new address[](1);
        res[0] = underlying;
    }

    function getTokensOut() external view returns (address[] memory res) {
        res = new address[](1);
        res[0] = address(this);
    }

    function isValidTokenIn(address token) external view returns (bool) {
        return token == underlying || token == address(this);
    }

    function isValidTokenOut(address token) external view returns (bool) {
        return token == address(this) || token == underlying;
    }

    function previewDeposit(address, uint256 amountTokenToDeposit) external pure returns (uint256 amountSharesOut) {
        amountSharesOut = amountTokenToDeposit;
    }

    function previewRedeem(address, uint256 amountSharesToRedeem) external pure returns (uint256 amountTokenOut) {
        amountTokenOut = amountSharesToRedeem;
    }

    function lastDeposit() external view returns (address tokenIn, uint256 amount, uint256 value) {
        return (lastDepositTokenIn, lastDepositAmount, lastDepositValue);
    }

    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        assetType = AssetType.TOKEN;
        assetAddress = underlying;
        assetDecimals = 18;
    }
}

contract RouterMockERC20 is OutrunERC20 {
    constructor(string memory name_, string memory symbol_) OutrunERC20(name_, symbol_, 18) {}

    function mint(address receiver, uint256 amount) external {
        _mint(receiver, amount);
    }
}

contract RouterMockUAsset is OutrunERC20, IUniversalAssets {
    mapping(address minter => MintingStatus) public mintingStatusTable;

    constructor() OutrunERC20("Mock UAsset", "mUAsset", 18) {}

    function checkMintableAmount(address minter) external view returns (uint256 amountInMintable) {
        MintingStatus storage status = mintingStatusTable[minter];
        amountInMintable = status.mintingCap > status.amountInMinted ? status.mintingCap - status.amountInMinted : 0;
    }

    function setMintingCap(address minter, uint256 mintingCap) public {
        mintingStatusTable[minter].mintingCap = mintingCap;
    }

    function revokeMinter(address minter) external {
        mintingStatusTable[minter].mintingCap = 0;
    }

    function mint(address receiver, uint256 amount) external {
        MintingStatus storage status = mintingStatusTable[msg.sender];
        require(status.amountInMinted + amount <= status.mintingCap, ReachMintCap());
        status.amountInMinted += amount;
        _mint(receiver, amount);
    }

    function repay(address account, uint256 amount) external {
        MintingStatus storage status = mintingStatusTable[msg.sender];
        require(status.amountInMinted >= amount, ReachBurnCap());
        _spendAllowance(account, msg.sender, amount);
        status.amountInMinted -= amount;
        _burn(account, amount);
    }
}

contract RouterMockLauncher {
    error RouterGenesisTransferFailed();

    RouterMockUAsset internal immutable uAsset;
    uint256 internal lastVerseId;
    uint128 internal lastAmountInUAsset;
    address internal lastUser;

    constructor(address uAsset_) {
        uAsset = RouterMockUAsset(uAsset_);
    }

    function genesis(uint256 verseId, uint128 amountInUAsset, address user) external {
        if (!uAsset.transferFrom(msg.sender, address(this), amountInUAsset)) revert RouterGenesisTransferFailed();
        lastVerseId = verseId;
        lastAmountInUAsset = amountInUAsset;
        lastUser = user;
    }

    function snapshot() external view returns (uint256 verseId, uint128 amountInUAsset, address user) {
        return (lastVerseId, lastAmountInUAsset, lastUser);
    }
}

contract OutrunRouterTest is Test {
    bytes4 internal constant NATIVE_AMOUNT_MISMATCH_SELECTOR = bytes4(keccak256("NativeAmountMismatch()"));
    RouterMockERC20 internal underlying;
    RouterMockSY internal sy;
    RouterMockUAsset internal uAsset;
    OutrunStakingPosition internal position;
    OutrunRouter internal router;
    RouterMockLauncher internal launcher;

    address internal owner = address(0xA11CE);
    address internal revenuePool = address(0xFEE);
    bytes4 internal constant INVALID_PARAM_SELECTOR = bytes4(keccak256("InvalidParam()"));

    function setUp() external {
        underlying = new RouterMockERC20("Mock Asset", "mAST");
        sy = new RouterMockSY(address(underlying));
        uAsset = new RouterMockUAsset();
        launcher = new RouterMockLauncher(address(uAsset));

        position = new OutrunStakingPosition(owner, 1, revenuePool, address(sy), address(uAsset));
        router = new OutrunRouter(owner, address(launcher));

        uAsset.setMintingCap(address(position), type(uint256).max);

        underlying.mint(owner, 1_000e18);
        sy.mintShares(owner, 1_000e18);

        vm.prank(owner);
        underlying.approve(address(router), type(uint256).max);

        vm.prank(owner);
        sy.approve(address(router), type(uint256).max);

        vm.prank(owner);
        sy.approve(address(position), type(uint256).max);

        vm.prank(owner);
        uAsset.approve(address(router), type(uint256).max);
    }

    function testMintSYFromTokenPullsCallerFundsAndKeepsRouterPrefund() external {
        address receiver = address(0xBEEF);

        underlying.mint(address(router), 50e18);

        vm.prank(owner);
        uint256 syOut = IOutrunRouterPrefundless(address(router))
            .mintSYFromToken(address(sy), address(underlying), receiver, 100e18, 0);

        assertEq(syOut, 100e18);
        assertEq(underlying.balanceOf(owner), 900e18);
        assertEq(underlying.balanceOf(address(router)), 50e18);
        assertEq(underlying.balanceOf(address(sy)), 100e18);
        assertEq(sy.balanceOf(receiver), 100e18);
    }

    function testMintSYFromTokenRevertsWhenERC20InputCarriesMsgValue() external {
        vm.deal(owner, 1);

        vm.prank(owner);
        vm.expectRevert(NATIVE_AMOUNT_MISMATCH_SELECTOR);
        IOutrunRouterPrefundless(address(router)).mintSYFromToken{value: 1}(
            address(sy), address(underlying), owner, 100e18, 0
        );
    }

    function testMintSYFromTokenSupportsNativePath() external {
        address receiver = address(0xBEEF);

        vm.deal(owner, 100e18);

        vm.prank(owner);
        uint256 syOut = IOutrunRouterPrefundless(address(router)).mintSYFromToken{value: 100e18}(
            address(sy), address(0), receiver, 100e18, 0
        );

        (address tokenIn, uint256 amount, uint256 value) = sy.lastDeposit();

        assertEq(syOut, 100e18);
        assertEq(sy.balanceOf(receiver), 100e18);
        assertEq(tokenIn, address(0));
        assertEq(amount, 100e18);
        assertEq(value, 100e18);
    }

    function testRedeemSyToTokenPullsCallerSharesAndKeepsPrefundedInternalBalance() external {
        address receiver = address(0xBEEF);

        sy.mintShares(address(sy), 40e18);

        vm.prank(owner);
        uint256 tokenOut = IOutrunRouterPrefundless(address(router))
            .redeemSyToToken(address(sy), receiver, address(underlying), 100e18, 0);

        assertEq(tokenOut, 100e18);
        assertEq(sy.balanceOf(owner), 900e18);
        assertEq(sy.balanceOf(address(sy)), 40e18);
        assertEq(underlying.balanceOf(receiver), 100e18);
    }

    function testWrapStakeFromSYMintsUAssetToRecipient() external {
        vm.prank(owner);
        // solhint-disable-next-line avoid-low-level-calls
        (bool ok, bytes memory data) = address(router)
            .call(
                abi.encodeWithSelector(
                    IOutrunRouter.wrapStakeFromSY.selector, address(sy), address(position), 100e18, owner
                )
            );

        assertTrue(ok, "wrapStakeFromSY missing");
        uint256 uAssetMinted = abi.decode(data, (uint256));

        assertEq(uAssetMinted, 100e18);
        assertEq(uAsset.balanceOf(owner), 100e18);
        assertEq(position.syWrapStaking(), 100e18);
    }

    function testPreviewWrapRedeemMatchesStakeManagerPreview() external {
        vm.prank(owner);
        position.wrapStake(100e18, owner);

        sy.setExchangeRate(15e17);

        // solhint-disable-next-line avoid-low-level-calls
        (bool ok, bytes memory data) = address(router)
            .staticcall(
                abi.encodeWithSelector(IOutrunRouter.previewWrapRedeem.selector, address(position), 40e18, address(sy))
            );

        assertTrue(ok, "previewWrapRedeem missing");
        uint256 amountOut = abi.decode(data, (uint256));

        assertEq(amountOut, 26_666666666666666666);
    }

    function testWrapRedeemPullsUAssetAndTransfersSYToReceiver() external {
        vm.prank(owner);
        position.wrapStake(100e18, owner);

        sy.setExchangeRate(15e17);

        vm.prank(owner);
        // solhint-disable-next-line avoid-low-level-calls
        (bool ok, bytes memory data) = address(router)
            .call(
                abi.encodeWithSelector(IOutrunRouter.wrapRedeem.selector, address(position), 40e18, owner, address(sy))
            );

        assertTrue(ok, "wrapRedeem missing");
        uint256 syOut = abi.decode(data, (uint256));

        assertEq(syOut, 26_666666666666666666);
        assertEq(uAsset.balanceOf(owner), 60e18);
        assertEq(sy.balanceOf(owner), 926_666666666666666666);
    }

    function testGenesisBySYUsesLockedStakeInsteadOfWrapStake() external {
        vm.prank(owner);
        router.genesisBySY(address(sy), address(position), 100e18, 30, 1, owner);

        (address positionOwner, uint256 syStaked, uint256 uAssetMinted,, uint128 deadline) = position.positions(1);
        (uint256 verseId, uint128 launcherUAsset, address launcherUser) = launcher.snapshot();

        assertEq(positionOwner, owner);
        assertEq(syStaked, 100e18);
        assertEq(uAssetMinted, 100e18);
        assertEq(position.syWrapStaking(), 0);
        assertEq(position.syTotalStaking(), 100e18);
        assertEq(uAsset.balanceOf(owner), 0);
        assertEq(uAsset.balanceOf(address(router)), 0);
        assertEq(uAsset.balanceOf(address(launcher)), 100e18);
        assertEq(verseId, 1);
        assertEq(launcherUAsset, 100e18);
        assertEq(launcherUser, owner);
        assertEq(deadline, block.timestamp + 30 days);
    }

    function testStakeFromSYRevertsWhenMintedBelowMinimumUAsset() external {
        IOutrunRouter.StakeParam memory stakeParam =
            IOutrunRouter.StakeParam({lockupDays: 30, minUAssetMinted: 101e18, owner: owner, receiver: address(0)});

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IOutrunRouter.InsufficientUAssetMinted.selector, 100e18, 101e18));
        router.stakeFromSY(address(sy), address(position), 100e18, stakeParam);
    }

    function testStakeFromSYMintsUAssetToReceiverWhenSpecified() external {
        address receiver = address(0xBEEF);

        IOutrunRouter.StakeParam memory stakeParam =
            IOutrunRouter.StakeParam({lockupDays: 30, minUAssetMinted: 0, owner: owner, receiver: receiver});

        vm.prank(owner);
        (uint256 positionId, uint256 uAssetMinted) =
            router.stakeFromSY(address(sy), address(position), 100e18, stakeParam);

        (address positionOwner, uint256 syStaked, uint256 positionUAssetMinted,, uint128 deadline) =
            position.positions(positionId);

        // Position is owned by owner
        assertEq(positionOwner, owner);
        assertEq(syStaked, 100e18);
        assertEq(positionUAssetMinted, 100e18);
        // uAsset is minted to receiver
        assertEq(uAsset.balanceOf(receiver), 100e18);
        assertEq(uAsset.balanceOf(owner), 0);
        assertEq(uAssetMinted, 100e18);
        assertEq(deadline, block.timestamp + 30 days);
    }

    function testStakeFromSYDefaultsReceiverToOwnerWhenZero() external {
        // receiver = address(0) should behave like the old code: uAsset goes to owner
        IOutrunRouter.StakeParam memory stakeParam =
            IOutrunRouter.StakeParam({lockupDays: 30, minUAssetMinted: 0, owner: owner, receiver: address(0)});

        vm.prank(owner);
        (uint256 positionId, uint256 uAssetMinted) =
            router.stakeFromSY(address(sy), address(position), 100e18, stakeParam);

        (address positionOwner, uint256 syStaked, uint256 positionUAssetMinted,,) = position.positions(positionId);

        // Position is owned by owner
        assertEq(positionOwner, owner);
        assertEq(syStaked, 100e18);
        assertEq(positionUAssetMinted, 100e18);
        // uAsset is minted to owner since receiver is address(0)
        assertEq(uAsset.balanceOf(owner), 100e18);
        assertEq(uAssetMinted, 100e18);
    }

    function testStakeFromTokenMintsUAssetToReceiverWhenSpecified() external {
        address receiver = address(0xBEEF);

        IOutrunRouter.StakeParam memory stakeParam =
            IOutrunRouter.StakeParam({lockupDays: 30, minUAssetMinted: 0, owner: owner, receiver: receiver});

        vm.prank(owner);
        (uint256 positionId, uint256 uAssetMinted) =
            router.stakeFromToken(address(sy), address(position), address(underlying), 100e18, stakeParam);

        (address positionOwner, uint256 syStaked, uint256 positionUAssetMinted,, uint128 deadline) =
            position.positions(positionId);

        // Position is owned by owner
        assertEq(positionOwner, owner);
        assertEq(syStaked, 100e18);
        assertEq(positionUAssetMinted, 100e18);
        // uAsset is minted to receiver
        assertEq(uAsset.balanceOf(receiver), 100e18);
        assertEq(uAsset.balanceOf(owner), 0);
        assertEq(uAssetMinted, 100e18);
        assertEq(deadline, block.timestamp + 30 days);
    }

    function testStakeFromTokenDefaultsReceiverToOwnerWhenZero() external {
        // receiver = address(0) should behave like the old code: uAsset goes to owner
        IOutrunRouter.StakeParam memory stakeParam =
            IOutrunRouter.StakeParam({lockupDays: 30, minUAssetMinted: 0, owner: owner, receiver: address(0)});

        vm.prank(owner);
        (uint256 positionId, uint256 uAssetMinted) =
            router.stakeFromToken(address(sy), address(position), address(underlying), 100e18, stakeParam);

        (address positionOwner, uint256 syStaked, uint256 positionUAssetMinted,,) = position.positions(positionId);

        // Position is owned by owner
        assertEq(positionOwner, owner);
        assertEq(syStaked, 100e18);
        assertEq(positionUAssetMinted, 100e18);
        // uAsset is minted to owner since receiver is address(0)
        assertEq(uAsset.balanceOf(owner), 100e18);
        assertEq(uAssetMinted, 100e18);
    }
}
