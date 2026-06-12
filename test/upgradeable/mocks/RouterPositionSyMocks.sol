// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

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
