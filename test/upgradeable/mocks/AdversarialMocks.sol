// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {OutrunStakingPositionUpgradeable} from "../../../src/position/OutrunStakingPositionUpgradeable.sol";
import {IOutrunStakeManager} from "../../../src/position/interfaces/IOutrunStakeManager.sol";
import {IStandardizedYield} from "../../../src/yield/interfaces/IStandardizedYield.sol";
import {IUniversalAssets} from "../../../src/assets/interfaces/IUniversalAssets.sol";

/**
 * @title MockSYWithRateControl
 * @notice Mock SY that allows rate manipulation for adversarial testing
 */
contract MockSYWithRateControl is ERC20, IStandardizedYield {
    address internal immutable underlying;
    uint256 internal rate;
    bool internal shouldReenterOnRedeem;
    address internal reentrancyTarget;
    bytes internal reentrancyCalldata;

    constructor(address underlying_) ERC20("Mock SY", "mSY") {
        underlying = underlying_;
        rate = 1e18;
    }

    function setExchangeRate(uint256 newRate) external {
        rate = newRate;
    }

    function setReentrancyOnRedeem(bool enabled, address target, bytes calldata data) external {
        shouldReenterOnRedeem = enabled;
        reentrancyTarget = target;
        reentrancyCalldata = data;
    }

    function mintShares(address receiver, uint256 amount) external {
        _mint(receiver, amount);
    }

    function deposit(address receiver, address, uint256 amountTokenToDeposit, uint256)
        external
        payable
        returns (uint256 amountSharesOut)
    {
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
            MockERC20ForAdversarial(tokenOut).mint(receiver, amountTokenOut);
        }

        // Attempt reentrancy if configured
        if (shouldReenterOnRedeem && reentrancyTarget != address(0)) {
            // solhint-disable-next-line avoid-low-level-calls
            (bool success,) = reentrancyTarget.call(reentrancyCalldata);
            // Intentionally ignore result - we're testing that reentrancy is blocked
            success;
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

    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        assetType = AssetType.TOKEN;
        assetAddress = underlying;
        assetDecimals = 18;
    }
}

/**
 * @title MockERC20ForAdversarial
 * @notice Simple mock ERC20 for adversarial tests
 */
contract MockERC20ForAdversarial is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address receiver, uint256 amount) external {
        _mint(receiver, amount);
    }
}

/**
 * @title MockUAssetForAdversarial
 * @notice Mock uAsset with mint cap tracking for adversarial tests
 */
contract MockUAssetForAdversarial is ERC20, IUniversalAssets {
    address public immutable owner;

    mapping(address minter => MintingStatus) public mintingStatusTable;

    error OwnableUnauthorizedAccount(address account);

    modifier onlyOwner() {
        require(msg.sender == owner, OwnableUnauthorizedAccount(msg.sender));
        _;
    }

    constructor() ERC20("Mock UAsset", "mUAsset") {
        owner = msg.sender;
    }

    function checkMintableAmount(address minter) external view returns (uint256 amountInMintable) {
        MintingStatus storage status = mintingStatusTable[minter];
        amountInMintable = status.mintingCap > status.amountInMinted ? status.mintingCap - status.amountInMinted : 0;
    }

    function setMintingCap(address minter, uint256 mintingCap) public onlyOwner {
        require(minter != address(0), ZeroInput());
        mintingStatusTable[minter].mintingCap = mintingCap;
    }

    function revokeMinter(address minter) external onlyOwner {
        require(minter != address(0), ZeroInput());
        mintingStatusTable[minter].mintingCap = 0;
    }

    function transferMinterDebt(address from, address to, uint256 amount) external onlyOwner {
        require(from != address(0) && to != address(0) && from != to && amount != 0, ZeroInput());

        MintingStatus storage fromStatus = mintingStatusTable[from];
        require(fromStatus.amountInMinted >= amount, ReachBurnCap());

        MintingStatus storage toStatus = mintingStatusTable[to];
        require(toStatus.mintingCap >= toStatus.amountInMinted, ReachMintCap());
        require(amount <= toStatus.mintingCap - toStatus.amountInMinted, ReachMintCap());

        fromStatus.amountInMinted -= amount;
        toStatus.amountInMinted += amount;
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

/**
 * @title MaliciousSY
 * @notice Malicious SY that attempts reentrancy attacks on position
 */
contract MaliciousSY is ERC20, IStandardizedYield {
    address internal immutable underlying;
    uint256 internal rate;
    OutrunStakingPositionUpgradeable internal targetPosition;
    bytes4 internal attackSelector;

    constructor(address underlying_) ERC20("Malicious SY", "malSY") {
        underlying = underlying_;
        rate = 1e18;
    }

    function setExchangeRate(uint256 newRate) external {
        rate = newRate;
    }

    function setAttackTarget(OutrunStakingPositionUpgradeable position, bytes4 selector) external {
        targetPosition = position;
        attackSelector = selector;
    }

    function mintShares(address receiver, uint256 amount) external {
        _mint(receiver, amount);
    }

    function deposit(address receiver, address, uint256 amountTokenToDeposit, uint256)
        external
        payable
        returns (uint256 amountSharesOut)
    {
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
            MockERC20ForAdversarial(tokenOut).mint(receiver, amountTokenOut);
        }

        // Attempt malicious reentrancy
        if (address(targetPosition) != address(0) && attackSelector != bytes4(0)) {
            // Try to call stake during redeem callback
            if (attackSelector == IOutrunStakeManager.stake.selector) {
                // solhint-disable-next-line avoid-low-level-calls
                // Adversarial test: intentionally ignore return value
                (bool success,) = address(targetPosition)
                    .call(abi.encodeWithSelector(attackSelector, 1e18, uint128(30), receiver, receiver));
                success; // suppress unused-variable warning
            }
            // Try to call drawUAsset during redeem callback
            else if (attackSelector == IOutrunStakeManager.drawUAsset.selector) {
                // Need a valid positionId - try with 1
                // Adversarial test: intentionally ignore return value
                // solhint-disable-next-line avoid-low-level-calls
                (bool success,) =
                    address(targetPosition).call(abi.encodeWithSelector(attackSelector, uint256(1), receiver));
                success; // suppress unused-variable warning
            }
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

    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        assetType = AssetType.TOKEN;
        assetAddress = underlying;
        assetDecimals = 18;
    }
}
