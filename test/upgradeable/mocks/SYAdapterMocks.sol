// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @notice Thrown when the caller tries to burn more scaled balance than they hold.
error NotEnoughAvailableUserBalance();

/// @notice Thrown when the computed scaled amount for a supply operation is zero.
error ScaledAmountIsZero();

/// @notice Minimal ERC-20 mock with a public `mint` helper.
contract MockToken is ERC20 {
    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) public virtual {
        _mint(to, amount);
    }
}

/// @notice Mock Aave aToken that tracks scaled balances with a configurable transfer index.
contract MockAToken is MockToken {
    uint256 private constant RAY = 1e27;

    address public immutable UNDERLYING_ASSET_ADDRESS;
    mapping(address => uint256) private scaledBalances;
    uint256 private scaledSupply;
    uint256 public transferIndex = RAY;

    constructor(address underlying_) MockToken("Aave aToken", "aTKN", 18) {
        UNDERLYING_ASSET_ADDRESS = underlying_;
    }

    function scaledBalanceOf(address user) external view returns (uint256) {
        return scaledBalances[user];
    }

    function getScaledUserBalanceAndSupply(address user) external view returns (uint256, uint256) {
        return (scaledBalances[user], scaledSupply);
    }

    function scaledTotalSupply() external view returns (uint256) {
        return scaledSupply;
    }

    function getPreviousIndex(address) external pure returns (uint256) {
        return 0;
    }

    function mintScaled(address to, uint256 amount) external {
        scaledBalances[to] += amount;
        scaledSupply += amount;
        _mint(to, amount);
    }

    function mint(address to, uint256 amount) public override {
        scaledBalances[to] += _rayDiv(amount, transferIndex);
        scaledSupply += _rayDiv(amount, transferIndex);
        _mint(to, amount);
    }

    function burnScaled(address from, uint256 amount) external {
        uint256 balance = scaledBalances[from];
        if (balance < amount) revert NotEnoughAvailableUserBalance();
        scaledBalances[from] = balance - amount;
        scaledSupply -= amount;
        _burn(from, amount);
    }

    function setTransferIndex(uint256 index_) external {
        transferIndex = index_;
    }

    function transfer(address to, uint256 value) public override returns (bool) {
        bool success = super.transfer(to, value);
        _moveScaled(msg.sender, to, _rayDiv(value, transferIndex));
        return success;
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        bool success = super.transferFrom(from, to, value);
        _moveScaled(from, to, _rayDiv(value, transferIndex));
        return success;
    }

    function _moveScaled(address from, address to, uint256 scaledAmount) private {
        uint256 fromBalance = scaledBalances[from];
        if (fromBalance < scaledAmount) revert NotEnoughAvailableUserBalance();
        scaledBalances[from] = fromBalance - scaledAmount;
        scaledBalances[to] += scaledAmount;
    }

    function _rayDiv(uint256 amount, uint256 ray) private pure returns (uint256) {
        return (amount * RAY + ray / 2) / ray;
    }
}

/// @notice Mock Aave pool with configurable reserve index for testing ray-math rounding.
contract MockAavePool {
    uint256 private constant RAY = 1e27;

    address public underlying;
    MockAToken public aToken;
    uint256 public index = RAY;

    function setReserve(address underlying_, MockAToken aToken_, uint256 index_) external {
        underlying = underlying_;
        aToken = aToken_;
        index = index_;
        aToken_.setTransferIndex(index_);
    }

    function supply(address asset, uint256 amount, address onBehalfOf, uint16) external {
        if (address(aToken) == address(0)) return;
        uint256 scaledAmount = _rayDiv(amount, index);
        if (scaledAmount == 0) revert ScaledAmountIsZero();
        MockToken(asset).transferFrom(msg.sender, address(this), amount);
        aToken.mintScaled(onBehalfOf, scaledAmount);
    }

    function withdraw(address asset, uint256 amount, address receiver) external returns (uint256) {
        if (address(aToken) == address(0)) return amount;
        uint256 scaledAmount = _rayDiv(amount, index);
        aToken.burnScaled(msg.sender, scaledAmount);
        MockToken(asset).transfer(receiver, amount);
        return amount;
    }

    function getReserveNormalizedIncome(address) external view returns (uint256) {
        return index;
    }

    function _rayDiv(uint256 amount, uint256 ray) private pure returns (uint256) {
        return (amount * RAY + ray / 2) / ray;
    }
}

/// @notice Minimal oracle mock returning a configurable exchange rate.
contract MockOracle {
    uint256 public rate;

    constructor(uint256 rate_) {
        rate = rate_;
    }

    function setExchangeRate(uint256 rate_) external {
        rate = rate_;
    }

    function getExchangeRate() external view returns (uint256) {
        return rate;
    }
}

/// @notice Trivial liquidity pool mock where shares equal amounts 1:1.
contract MockLiquidityPool {
    function amountForShare(uint256 shares) external pure returns (uint256) {
        return shares;
    }

    function sharesForAmount(uint256 amount) external pure returns (uint256) {
        return amount;
    }
}

/// @notice Mock Wrapped eETH that mints/burns 1:1 against a backing eETH token.
contract MockWeETH is MockToken {
    address public immutable EETH;

    constructor(address eETH_) MockToken("Wrapped eETH", "weETH", 18) {
        EETH = eETH_;
    }

    function wrap(uint256 amount) external returns (uint256) {
        MockToken(EETH).transferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, amount);
        return amount;
    }

    function unwrap(uint256 amount) external returns (uint256) {
        _burn(msg.sender, amount);
        MockToken(EETH).mint(msg.sender, amount);
        return amount;
    }
}

/// @notice Mock stETH with trivial share-to-ETH conversions.
contract MockStETH is MockToken {
    constructor() MockToken("stETH", "stETH", 18) {}

    function getSharesByPooledEth(uint256 amount) external pure returns (uint256) {
        return amount;
    }

    function getPooledEthByShares(uint256 amount) external pure returns (uint256) {
        return amount;
    }

    function submit(address) external payable returns (uint256) {
        _mint(msg.sender, msg.value);
        return msg.value;
    }
}

/// @notice Mock wstETH that wraps/unwraps 1:1 against a backing stETH token.
contract MockWstETH is MockToken {
    address public immutable STETH;

    constructor(address stETH_) MockToken("Wrapped stETH", "wstETH", 18) {
        STETH = stETH_;
    }

    function stEthPerToken() external pure returns (uint256) {
        return 1e18;
    }

    function getWstETHByStETH(uint256 amount) external pure returns (uint256) {
        return amount;
    }

    function getStETHByWstETH(uint256 amount) external pure returns (uint256) {
        return amount;
    }

    function wrap(uint256 amount) external returns (uint256) {
        MockToken(STETH).transferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, amount);
        return amount;
    }

    function unwrap(uint256 amount) external returns (uint256) {
        _burn(msg.sender, amount);
        MockToken(STETH).mint(msg.sender, amount);
        return amount;
    }
}

/// @notice Mock L2 stETH that converts between shares and tokens via a configurable TOKENS_PER_SHARE ratio.
contract MockL2StETH is MockToken {
    address public immutable WSTETH;
    uint256 public immutable TOKENS_PER_SHARE;

    constructor(address wstETH_, uint256 tokensPerShare_) MockToken("L2 stETH", "stETH", 18) {
        WSTETH = wstETH_;
        TOKENS_PER_SHARE = tokensPerShare_;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return getTokensByShares(super.balanceOf(account));
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        _transfer(msg.sender, to, getSharesByTokens(amount));
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, getSharesByTokens(amount));
        return true;
    }

    function wrap(uint256 sharesAmount) external returns (uint256) {
        MockToken(WSTETH).transferFrom(msg.sender, address(this), sharesAmount);
        uint256 tokenAmount = getTokensByShares(sharesAmount);
        _mint(msg.sender, sharesAmount);
        return tokenAmount;
    }

    function unwrap(uint256 tokenAmount) external returns (uint256) {
        uint256 sharesAmount = getSharesByTokens(tokenAmount);
        _burn(msg.sender, sharesAmount);
        MockToken(WSTETH).mint(msg.sender, sharesAmount);
        return sharesAmount;
    }

    function getTokensByShares(uint256 sharesAmount) public view returns (uint256) {
        return (sharesAmount * TOKENS_PER_SHARE) / 1 ether;
    }

    function getSharesByTokens(uint256 tokenAmount) public view returns (uint256) {
        return (tokenAmount * 1 ether) / TOKENS_PER_SHARE;
    }
}

/// @notice Mock ERC-4626 vault where shares equal assets 1:1.
contract MockVault is MockToken, IERC4626 {
    address public immutable ASSET;

    constructor(address asset_) MockToken("Vault", "vTKN", 18) {
        ASSET = asset_;
    }

    function asset() external view returns (address) {
        return ASSET;
    }

    function totalAssets() external view returns (uint256) {
        return totalSupply();
    }

    function convertToShares(uint256 assets) public pure returns (uint256) {
        return assets;
    }

    function convertToAssets(uint256 shares) public pure returns (uint256) {
        return shares;
    }

    function maxDeposit(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function previewDeposit(uint256 assets) external pure returns (uint256) {
        return assets;
    }

    function deposit(uint256 assets, address receiver) external returns (uint256) {
        _mint(receiver, assets);
        return assets;
    }

    function maxMint(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function previewMint(uint256 shares) external pure returns (uint256) {
        return shares;
    }

    function mint(uint256 shares, address receiver) external returns (uint256) {
        _mint(receiver, shares);
        return shares;
    }

    function maxWithdraw(address owner) external view returns (uint256) {
        return balanceOf(owner);
    }

    function previewWithdraw(uint256 assets) external pure returns (uint256) {
        return assets;
    }

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256) {
        _burn(owner, assets);
        MockToken(ASSET).mint(receiver, assets);
        return assets;
    }

    function maxRedeem(address owner) external view returns (uint256) {
        return balanceOf(owner);
    }

    function previewRedeem(uint256 shares) external pure returns (uint256) {
        return shares;
    }

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256) {
        _burn(owner, shares);
        MockToken(ASSET).mint(receiver, shares);
        return shares;
    }
}

/// @notice Mock PSM3 that swaps tokens 1:1 via mint-on-receive.
contract MockPSM3 {
    function swapExactIn(address tokenIn, address tokenOut, uint256 amountIn, uint256, address receiver, uint256)
        external
        returns (uint256)
    {
        MockToken(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        MockToken(tokenOut).mint(receiver, amountIn);
        return amountIn;
    }

    function previewSwapExactIn(address, address, uint256 amountIn) external pure returns (uint256) {
        return amountIn;
    }
}

/// @notice Mock Lista stake manager with trivial BNB-to-slisBNB conversions.
contract MockListaStakeManager {
    function deposit() external payable {}

    function convertSnBnbToBnb(uint256 amount) external pure returns (uint256) {
        return amount;
    }

    function convertBnbToSnBnb(uint256 amount) external pure returns (uint256) {
        return amount;
    }
}

/// @notice Mock yield proxy that stores a stake manager reference.
contract MockYieldProxy {
    address public stakeManager;
    bool public activitiesOnGoing;

    constructor(address stakeManager_) {
        stakeManager = stakeManager_;
    }
}

/// @notice Mock asBNB minter with trivial mint and conversion helpers.
contract MockAsBnbMinter {
    address public asBnb;
    address public token;
    address public yieldProxy;

    constructor(address asBnb_, address token_, address yieldProxy_) {
        asBnb = asBnb_;
        token = token_;
        yieldProxy = yieldProxy_;
    }

    function mintAsBnb() external payable returns (uint256) {
        return msg.value;
    }

    function mintAsBnb(uint256 amount) external pure returns (uint256) {
        return amount;
    }

    function convertToTokens(uint256 amount) external pure returns (uint256) {
        return amount;
    }

    function convertToAsBnb(uint256 amount) external pure returns (uint256) {
        return amount;
    }
}
