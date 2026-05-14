// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {OutrunL2StakedTokenSYUpgradeable} from "../../src/yield/OutrunL2StakedTokenSYUpgradeable.sol";
import {OutrunStakedUsdsSYUpgradeable} from "../../src/yield/adapters/sky/OutrunStakedUsdsSYUpgradeable.sol";
import {ProxyTestHelper} from "./helpers/ProxyTestHelper.sol";

// ---- Mock assets ----
contract MockWstETH is ERC20 {
    constructor() ERC20("Wrapped stETH", "wstETH") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockUSDS is ERC20 {
    constructor() ERC20("Sky USDS", "USDS") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockSUSDS is ERC20, IERC4626 {
    address public immutable ASSET;
    uint256 public exchangeRateMultiplier = 1e18;

    constructor(address asset_) ERC20("Staked USDS", "sUSDS") {
        ASSET = asset_;
    }

    function mintShares(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        return assets * 1e18 / exchangeRateMultiplier;
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        return shares * exchangeRateMultiplier / 1e18;
    }

    function deposit(uint256 assets, address receiver) external returns (uint256) {
        MockUSDS(ASSET).transferFrom(msg.sender, address(this), assets);
        uint256 shares = convertToShares(assets);
        _mint(receiver, shares);
        return shares;
    }

    function mint(uint256 shares, address receiver) external returns (uint256 assets) {
        assets = convertToAssets(shares);
        MockUSDS(ASSET).transferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
        return assets;
    }

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256) {
        if (msg.sender != owner) _spendAllowance(owner, msg.sender, shares);
        uint256 assets = convertToAssets(shares);
        _burn(owner, shares);
        MockUSDS(ASSET).transfer(receiver, assets);
        return assets;
    }

    function asset() external view returns (address) {
        return ASSET;
    }

    function totalAssets() external view returns (uint256) {
        return totalSupply() * exchangeRateMultiplier / 1e18;
    }

    function previewDeposit(uint256 assets) external pure returns (uint256) {
        return assets;
    }

    function previewRedeem(uint256 shares) external pure returns (uint256) {
        return shares;
    }

    function maxDeposit(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function previewMint(uint256) external pure returns (uint256) {
        return 0;
    }

    function maxMint(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address) external view returns (uint256) {
        return convertToAssets(balanceOf(msg.sender));
    }

    function maxRedeem(address) external view returns (uint256) {
        return balanceOf(msg.sender);
    }

    function previewWithdraw(uint256) external pure returns (uint256) {
        return 0;
    }

    function withdraw(uint256, address, address) external pure returns (uint256) {
        return 0;
    }
}

contract MockExchangeOracle {
    uint256 public exchangeRateValue = 1e18;

    function setExchangeRate(uint256 rate) external {
        exchangeRateValue = rate;
    }

    function getExchangeRate() external view returns (uint256) {
        return exchangeRateValue;
    }
}

// ---- Mock Position Manager ----
contract MockPositionManager {
    address public immutable yieldBearingToken;
    uint256 public nextPositionId = 1;
    uint256 public totalPositionUAsset;
    uint256 public constant MIN_STAKE_AMOUNT = 1 ether;
    uint256 public constant REDEEM_FEE_BPS = 50;

    struct Position {
        address owner;
        uint256 uAssetStaked;
        bool locked;
        uint256 createdAt;
        uint256 lockDuration;
        address syToken;
    }

    mapping(uint256 => Position) public positions;
    mapping(address => uint256[]) public positionIdsOf;

    event Stake(uint256 indexed positionId, address indexed owner, uint256 amount);
    event Redeem(uint256 indexed positionId, address indexed owner, uint256 amount);

    constructor(address _yieldBearingToken) {
        yieldBearingToken = _yieldBearingToken;
    }

    function stake(address owner, uint256 amount) external returns (uint256 positionId) {
        require(amount >= MIN_STAKE_AMOUNT, "below minimum");
        IERC20(yieldBearingToken).transferFrom(msg.sender, address(this), amount);
        positionId = nextPositionId++;
        positions[positionId] = Position({
            owner: owner,
            uAssetStaked: amount,
            locked: false,
            createdAt: block.timestamp,
            lockDuration: 30 days,
            syToken: address(0)
        });
        positionIdsOf[owner].push(positionId);
        totalPositionUAsset += amount;
        emit Stake(positionId, owner, amount);
    }

    function redeem(address caller, uint256 positionId, uint256 amount) external returns (uint256 redeemed) {
        Position storage pos = positions[positionId];
        require(pos.owner == caller || msg.sender == pos.owner, "not owner");
        require(amount <= pos.uAssetStaked, "exceeds stake");
        uint256 netAmount = (amount * (10000 - REDEEM_FEE_BPS)) / 10000;
        pos.uAssetStaked -= amount;
        redeemed = netAmount;
        totalPositionUAsset -= amount;
        IERC20(yieldBearingToken).transfer(caller, redeemed);
        emit Redeem(positionId, caller, amount);
    }

    function redeemAll(address caller, uint256 positionId) external returns (uint256 redeemed) {
        Position storage pos = positions[positionId];
        require(pos.owner == caller || msg.sender == pos.owner, "not owner");
        redeemed = (pos.uAssetStaked * (10000 - REDEEM_FEE_BPS)) / 10000;
        totalPositionUAsset -= pos.uAssetStaked;
        IERC20(yieldBearingToken).transfer(caller, redeemed);
        emit Redeem(positionId, caller, pos.uAssetStaked);
    }
}

contract RouterPositionSyTest is Test {
    address internal constant OWNER = address(0xA11CE);
    address internal constant USER = address(0xB0B);

    uint256 internal constant STAKE_AMOUNT = 100 ether;

    MockWstETH internal wstETH;
    MockExchangeOracle internal oracle;
    OutrunL2StakedTokenSYUpgradeable internal sy;
    MockPositionManager internal position;

    function setUp() external {
        wstETH = new MockWstETH();
        oracle = new MockExchangeOracle();
        sy = OutrunL2StakedTokenSYUpgradeable(
            payable(ProxyTestHelper.deploy(
                    address(new OutrunL2StakedTokenSYUpgradeable()),
                    abi.encodeCall(
                        OutrunL2StakedTokenSYUpgradeable.initialize,
                        ("SY wstETH", "SYw", OWNER, address(wstETH), address(oracle), address(wstETH), 18)
                    )
                ))
        );
        position = new MockPositionManager(address(wstETH));
    }

    function test_GenesisStakeRedeemFullCycle() external {
        wstETH.mint(USER, STAKE_AMOUNT * 10);
        wstETH.mint(OWNER, STAKE_AMOUNT);

        // User deposits tokens into SY
        vm.prank(USER);
        wstETH.approve(address(sy), STAKE_AMOUNT);
        vm.prank(USER);
        uint256 sharesOut = sy.deposit(USER, address(wstETH), STAKE_AMOUNT, 0);

        assertEq(sharesOut, STAKE_AMOUNT);
        assertEq(sy.balanceOf(USER), STAKE_AMOUNT);

        // OWNER stakes wstETH into position directly
        vm.startPrank(OWNER);
        wstETH.approve(address(position), STAKE_AMOUNT);
        uint256 positionId = position.stake(OWNER, STAKE_AMOUNT);
        vm.stopPrank();

        assertEq(position.totalPositionUAsset(), STAKE_AMOUNT);

        // Transfer SY shares to OWNER for bookkeeping
        vm.prank(USER);
        sy.transfer(OWNER, sharesOut);

        // Redeem from position
        vm.prank(OWNER);
        uint256 redeemed = position.redeemAll(OWNER, positionId);

        assertGt(redeemed, 0);
        assertEq(position.totalPositionUAsset(), 0);

        uint256 expectedRedeem = (STAKE_AMOUNT * (10000 - 50)) / 10000;
        assertEq(redeemed, expectedRedeem);
    }

    function test_PartialRedemptionsPreserveAccounting() external {
        wstETH.mint(OWNER, STAKE_AMOUNT * 2);
        vm.startPrank(OWNER);
        wstETH.approve(address(position), STAKE_AMOUNT);

        uint256 positionId = position.stake(OWNER, STAKE_AMOUNT);

        uint256 firstRedeem = (STAKE_AMOUNT * 30) / 100;
        uint256 redeemed1 = position.redeem(OWNER, positionId, firstRedeem);

        uint256 expectedFirstRedeem = (firstRedeem * (10000 - 50)) / 10000;
        assertEq(redeemed1, expectedFirstRedeem);

        uint256 expectedRemaining = STAKE_AMOUNT - firstRedeem;
        (, uint256 remainingStake,,,,) = position.positions(positionId);
        assertEq(remainingStake, expectedRemaining);

        assertEq(position.totalPositionUAsset(), expectedRemaining);

        // Second partial redeem
        uint256 secondRedeem = (STAKE_AMOUNT * 30) / 100;
        uint256 redeemed2 = position.redeem(OWNER, positionId, secondRedeem);
        uint256 expectedSecondRedeem = (secondRedeem * (10000 - 50)) / 10000;
        assertEq(redeemed2, expectedSecondRedeem);

        uint256 finalRemaining = expectedRemaining - secondRedeem;
        (, remainingStake,,,,) = position.positions(positionId);
        assertEq(remainingStake, finalRemaining);
        assertEq(position.totalPositionUAsset(), finalRemaining);

        vm.stopPrank();
    }

    function test_ExchangeRateChangeMidCycle() external {
        wstETH.mint(USER, STAKE_AMOUNT * 10);

        vm.prank(USER);
        wstETH.approve(address(sy), STAKE_AMOUNT);
        vm.prank(USER);
        uint256 sharesOut = sy.deposit(USER, address(wstETH), STAKE_AMOUNT, 0);
        assertEq(sharesOut, STAKE_AMOUNT);

        // Exchange rate changes (yield accrual)
        oracle.setExchangeRate(1.1e18);
        uint256 newRate = sy.exchangeRate();
        assertEq(newRate, 1.1e18);

        assertEq(sy.balanceOf(USER), STAKE_AMOUNT);
    }

    function test_KeepRedeemDoesNotBlockOtherUsers() external {
        address user1 = address(0x1111);
        address user2 = address(0x2222);
        uint256 stake1 = 100 ether;
        uint256 stake2 = 50 ether;

        wstETH.mint(user1, stake1 * 2);
        wstETH.mint(user2, stake2 * 2);

        vm.prank(user1);
        wstETH.approve(address(position), stake1);
        vm.prank(user1);
        position.stake(user1, stake1);

        vm.prank(user2);
        wstETH.approve(address(position), stake2);
        vm.prank(user2);
        uint256 posId2 = position.stake(user2, stake2);

        // user1 redeems all
        vm.prank(user1);
        position.redeemAll(user1, 1);

        (, uint256 remainingStake,,,,) = position.positions(posId2);
        assertEq(remainingStake, stake2);
        assertEq(position.totalPositionUAsset(), stake2);
    }

    function test_RouterMultiProtocolRouting() external {
        MockUSDS usds = new MockUSDS();
        MockSUSDS sUSDS = new MockSUSDS(address(usds));

        OutrunStakedUsdsSYUpgradeable sy2 = OutrunStakedUsdsSYUpgradeable(
            payable(ProxyTestHelper.deploy(
                    address(new OutrunStakedUsdsSYUpgradeable()),
                    abi.encodeCall(OutrunStakedUsdsSYUpgradeable.initialize, (OWNER, address(usds), address(sUSDS)))
                ))
        );

        usds.mint(USER, STAKE_AMOUNT * 10);
        sUSDS.mintShares(USER, STAKE_AMOUNT);

        vm.startPrank(USER);
        usds.approve(address(sy2), type(uint256).max);
        sUSDS.approve(address(sy2), type(uint256).max);

        uint256 sharesOut = sy2.deposit(USER, address(usds), STAKE_AMOUNT, 0);
        assertEq(sharesOut, STAKE_AMOUNT);
        assertEq(sy2.balanceOf(USER), STAKE_AMOUNT);

        assertEq(sy.balanceOf(USER), 0, "first SY balance should be unaffected");

        vm.stopPrank();
    }
}
