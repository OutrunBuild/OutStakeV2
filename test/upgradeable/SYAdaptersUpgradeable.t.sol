// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {OutrunL2StakedTokenSYUpgradeable} from "../../src/yield/OutrunL2StakedTokenSYUpgradeable.sol";
import {OutrunAaveV3SYUpgradeable} from "../../src/yield/adapters/aave/OutrunAaveV3SYUpgradeable.sol";
import {OutrunWeETHSYUpgradeable} from "../../src/yield/adapters/etherfi/OutrunWeETHSYUpgradeable.sol";
import {OutrunWstETHSYUpgradeable} from "../../src/yield/adapters/lido/OutrunWstETHSYUpgradeable.sol";
import {OutrunL2WstETHSYUpgradeable} from "../../src/yield/adapters/lido/OutrunL2WstETHSYUpgradeable.sol";
import {
    OutrunL2WrappableWstETHSYUpgradeable
} from "../../src/yield/adapters/lido/OutrunL2WrappableWstETHSYUpgradeable.sol";
import {OutrunStakedUSDeSYUpgradeable} from "../../src/yield/adapters/ethena/OutrunStakedUSDeSYUpgradeable.sol";
import {OutrunStakedUsdsSYUpgradeable} from "../../src/yield/adapters/sky/OutrunStakedUsdsSYUpgradeable.sol";
import {OutrunL2StakedUsdsSYUpgradeable} from "../../src/yield/adapters/sky/OutrunL2StakedUsdsSYUpgradeable.sol";
import {OutrunSlisBNBSYUpgradeable} from "../../src/yield/adapters/lista/OutrunSlisBNBSYUpgradeable.sol";
import {OutrunAsBNBSYUpgradeable} from "../../src/yield/adapters/aster/OutrunAsBNBSYUpgradeable.sol";
import {ProxyTestHelper} from "./helpers/ProxyTestHelper.sol";

contract MockToken is ERC20 {
    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) public virtual {
        _mint(to, amount);
    }
}

contract TestOutrunL2StakedTokenSYUpgradeable is OutrunL2StakedTokenSYUpgradeable {
    function exposedRedeem(address receiver, address tokenOut, uint256 amountSharesToRedeem)
        external
        returns (uint256)
    {
        return _redeem(receiver, tokenOut, amountSharesToRedeem);
    }
}

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

error NotEnoughAvailableUserBalance();
error ScaledAmountIsZero();

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

contract MockLiquidityPool {
    function amountForShare(uint256 shares) external pure returns (uint256) {
        return shares;
    }

    function sharesForAmount(uint256 amount) external pure returns (uint256) {
        return amount;
    }
}

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

contract MockListaStakeManager {
    function deposit() external payable {}

    function convertSnBnbToBnb(uint256 amount) external pure returns (uint256) {
        return amount;
    }

    function convertBnbToSnBnb(uint256 amount) external pure returns (uint256) {
        return amount;
    }
}

contract MockYieldProxy {
    address public stakeManager;
    bool public activitiesOnGoing;

    constructor(address stakeManager_) {
        stakeManager = stakeManager_;
    }
}

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

contract SYAdaptersUpgradeableTest is Test {
    address internal owner = address(0xA11CE);
    address internal user = address(0xB0B);
    address internal constant NATIVE = address(0);
    uint256 internal constant AMOUNT = 10 ether;
    MockToken internal token;
    MockOracle internal oracle;

    function setUp() external {
        token = new MockToken("Token", "TKN", 18);
        oracle = new MockOracle(1.2e18);
    }

    function testAllAdaptersInitializeBehindProxy() external {
        _assertSY(_deployL2Staked(), "SY Generic", "SYG", address(token));

        MockToken underlying = new MockToken("Underlying", "UND", 18);
        MockAToken aToken = new MockAToken(address(underlying));
        MockAavePool aavePool = new MockAavePool();
        OutrunAaveV3SYUpgradeable aaveImpl = new OutrunAaveV3SYUpgradeable();
        address aave = ProxyTestHelper.deploy(
            address(aaveImpl),
            abi.encodeCall(
                OutrunAaveV3SYUpgradeable.initialize, ("SY Aave", "SYA", address(aToken), address(aavePool), owner)
            )
        );
        _assertSY(aave, "SY Aave", "SYA", address(aToken));

        _assertSY(_deployWeETH(), "SY Etherfi weETH", "SY weETH", address(token));
        _assertSY(_deployWstETH(), "SY Lido wstETH", "SY wstETH", address(token));
        _assertSY(_deployL2WstETH(), "SY Lido wstETH", "SY wstETH", address(token));
        _assertSY(_deployL2WrappableWstETH(), "SY Lido wstETH", "SY wstETH", address(token));
        _assertSY(_deployEthena(), "SY Ethena sUSDe", "SY sUSDe", address(token));
        _assertSY(_deploySky(), "SY Sky sUSDS", "SY sUSDS", address(token));
        _assertSY(_deploySkyL2(), "SY Sky sUSDS", "SY sUSDS", address(token));
        _assertSY(_deployLista(), "SY Lista slisBNB", "SY slisBNB", address(token));
        _assertSY(_deployAster(), "SY Aster asBNB", "SY asBNB", address(token));
    }

    function testWstETHInitializerRevertsWhenWstETHIsZero() external {
        OutrunWstETHSYUpgradeable impl = new OutrunWstETHSYUpgradeable();
        MockToken stETH = new MockToken("stETH", "stETH", 18);

        vm.expectRevert();
        ProxyTestHelper.deploy(
            address(impl), abi.encodeCall(OutrunWstETHSYUpgradeable.initialize, (owner, address(stETH), address(0)))
        );
    }

    function testL2WrappableWstETHStoresUnderlyingImmediatelyAfterStETH() external {
        MockToken stETH = new MockToken("stETH", "stETH", 18);
        MockToken wstETH = new MockToken("wstETH", "wstETH", 18);
        MockToken underlyingOnEth = new MockToken("ETH", "ETH", 18);
        address sy = ProxyTestHelper.deploy(
            address(new OutrunL2WrappableWstETHSYUpgradeable()),
            abi.encodeCall(
                OutrunL2WrappableWstETHSYUpgradeable.initialize,
                (owner, address(stETH), address(wstETH), address(underlyingOnEth), 18)
            )
        );

        bytes32 storageSlot = _erc7201("outrun.storage.OutrunL2WrappableWstETHSY");

        assertEq(_storedAddress(sy, storageSlot), address(stETH));
        assertEq(_storedAddress(sy, bytes32(uint256(storageSlot) + 1)), address(underlyingOnEth));
    }

    function testOracleSetterIsOwnerOnlyAndAffectsExchangeRate() external {
        address sy = _deployL2Staked();
        assertEq(_asSY(sy).exchangeRate(), 1.2e18);

        MockOracle newOracle = new MockOracle(1.5e18);
        vm.prank(address(0xB0B));
        vm.expectRevert();
        _asSY(sy).setExchangeRateOracle(address(newOracle));

        vm.prank(owner);
        _asSY(sy).setExchangeRateOracle(address(newOracle));

        assertEq(_asSY(sy).exchangeRateOracle(), address(newOracle));
        assertEq(_asSY(sy).exchangeRate(), 1.5e18);

        vm.prank(owner);
        vm.expectRevert();
        _asSY(sy).setExchangeRateOracle(address(0));
    }

    function testAaveATokenRoundtripMatchesPreviewAndExchangeRate() external {
        MockToken underlying = new MockToken("Underlying", "UND", 18);
        MockAToken aToken = new MockAToken(address(underlying));
        MockAavePool aavePool = new MockAavePool();
        address sy = ProxyTestHelper.deploy(
            address(new OutrunAaveV3SYUpgradeable()),
            abi.encodeCall(
                OutrunAaveV3SYUpgradeable.initialize, ("SY Aave", "SYA", address(aToken), address(aavePool), owner)
            )
        );

        _assertYieldTokenRoundtrip(sy, aToken, AMOUNT);
        assertEq(_asSY(sy).exchangeRate(), 1e18);
    }

    function testAaveUnderlyingDepositMatchesAaveRayDivScaledDelta() external {
        uint256 amount = 3;
        MockToken underlying = new MockToken("Underlying", "UND", 18);
        MockAToken aToken = new MockAToken(address(underlying));
        MockAavePool aavePool = new MockAavePool();
        aavePool.setReserve(address(underlying), aToken, 2e27);
        address sy = ProxyTestHelper.deploy(
            address(new OutrunAaveV3SYUpgradeable()),
            abi.encodeCall(
                OutrunAaveV3SYUpgradeable.initialize, ("SY Aave", "SYA", address(aToken), address(aavePool), owner)
            )
        );

        underlying.mint(user, amount);
        vm.startPrank(user);
        underlying.approve(sy, amount);
        uint256 scaledBefore = aToken.scaledBalanceOf(sy);
        uint256 previewShares = _asSY(sy).previewDeposit(address(underlying), amount);
        uint256 sharesOut = _asSY(sy).deposit(user, address(underlying), amount, 0);
        uint256 scaledDelta = aToken.scaledBalanceOf(sy) - scaledBefore;
        vm.stopPrank();

        assertEq(previewShares, 2);
        assertEq(sharesOut, 2);
        assertEq(sharesOut, previewShares);
        assertEq(sharesOut, scaledDelta);
    }

    function testAaveATokenDepositUsesAaveRayDivRounding() external {
        uint256 amount = 3;
        MockToken underlying = new MockToken("Underlying", "UND", 18);
        MockAToken aToken = new MockAToken(address(underlying));
        MockAavePool aavePool = new MockAavePool();
        aavePool.setReserve(address(underlying), aToken, 2e27);
        address sy = ProxyTestHelper.deploy(
            address(new OutrunAaveV3SYUpgradeable()),
            abi.encodeCall(
                OutrunAaveV3SYUpgradeable.initialize, ("SY Aave", "SYA", address(aToken), address(aavePool), owner)
            )
        );

        aToken.mintScaled(user, amount);
        vm.startPrank(user);
        aToken.approve(sy, amount);
        uint256 scaledBefore = aToken.scaledBalanceOf(sy);
        uint256 previewShares = _asSY(sy).previewDeposit(address(aToken), amount);
        uint256 sharesOut = _asSY(sy).deposit(user, address(aToken), amount, 0);
        uint256 scaledDelta = aToken.scaledBalanceOf(sy) - scaledBefore;
        vm.stopPrank();

        assertEq(previewShares, 2);
        assertEq(sharesOut, 2);
        assertEq(sharesOut, scaledDelta);
    }

    function testAaveUnderlyingDepositThatRoundsToZeroReverts() external {
        uint256 amount = 1;
        MockToken underlying = new MockToken("Underlying", "UND", 18);
        MockAToken aToken = new MockAToken(address(underlying));
        MockAavePool aavePool = new MockAavePool();
        aavePool.setReserve(address(underlying), aToken, 3e27);
        address sy = ProxyTestHelper.deploy(
            address(new OutrunAaveV3SYUpgradeable()),
            abi.encodeCall(
                OutrunAaveV3SYUpgradeable.initialize, ("SY Aave", "SYA", address(aToken), address(aavePool), owner)
            )
        );

        underlying.mint(user, amount);
        vm.startPrank(user);
        underlying.approve(sy, amount);
        vm.expectRevert();
        _asSY(sy).deposit(user, address(underlying), amount, 0);
        vm.stopPrank();
    }

    function testL2StakedRedeemTransfersRequestedTokenOut() external {
        MockToken tokenOut = new MockToken("Token Out", "OUT", 18);
        TestOutrunL2StakedTokenSYUpgradeable impl = new TestOutrunL2StakedTokenSYUpgradeable();
        TestOutrunL2StakedTokenSYUpgradeable sy = TestOutrunL2StakedTokenSYUpgradeable(
            payable(ProxyTestHelper.deploy(
                    address(impl),
                    abi.encodeCall(
                        OutrunL2StakedTokenSYUpgradeable.initialize,
                        ("SY Generic", "SYG", owner, address(token), address(oracle), address(token), 18)
                    )
                ))
        );

        token.mint(address(sy), AMOUNT);
        tokenOut.mint(address(sy), AMOUNT);
        uint256 redeemed = sy.exposedRedeem(user, address(tokenOut), AMOUNT);

        assertEq(redeemed, AMOUNT);
        assertEq(token.balanceOf(user), 0);
        assertEq(tokenOut.balanceOf(user), AMOUNT);
    }

    function testWeEtheEthRoundtripMatchesPreviewAndExchangeRate() external {
        MockToken eETH = new MockToken("eETH", "eETH", 18);
        MockWeETH weETH = new MockWeETH(address(eETH));
        MockLiquidityPool pool = new MockLiquidityPool();
        address sy = ProxyTestHelper.deploy(
            address(new OutrunWeETHSYUpgradeable()),
            abi.encodeCall(
                OutrunWeETHSYUpgradeable.initialize,
                (owner, address(eETH), address(weETH), address(0xDAD), address(pool))
            )
        );

        eETH.mint(user, AMOUNT);
        vm.startPrank(user);
        eETH.approve(sy, AMOUNT);
        uint256 previewShares = _asSY(sy).previewDeposit(address(eETH), AMOUNT);
        uint256 sharesOut = _asSY(sy).deposit(user, address(eETH), AMOUNT, 0);
        uint256 previewOut = _asSY(sy).previewRedeem(address(eETH), sharesOut);
        uint256 redeemed = _asSY(sy).redeem(user, sharesOut, address(eETH), 0, false);
        vm.stopPrank();

        assertEq(sharesOut, previewShares);
        assertEq(redeemed, previewOut);
        assertEq(redeemed, AMOUNT);
        assertEq(eETH.balanceOf(user), AMOUNT);
        assertEq(weETH.balanceOf(sy), 0);
        assertEq(_asSY(sy).exchangeRate(), 1e18);
    }

    function testWstEthStEthRoundtripMatchesPreviewAndExchangeRate() external {
        MockStETH stETH = new MockStETH();
        MockWstETH wstETH = new MockWstETH(address(stETH));
        address sy = ProxyTestHelper.deploy(
            address(new OutrunWstETHSYUpgradeable()),
            abi.encodeCall(OutrunWstETHSYUpgradeable.initialize, (owner, address(stETH), address(wstETH)))
        );

        stETH.mint(user, AMOUNT);
        vm.startPrank(user);
        stETH.approve(sy, AMOUNT);
        uint256 previewShares = _asSY(sy).previewDeposit(address(stETH), AMOUNT);
        uint256 sharesOut = _asSY(sy).deposit(user, address(stETH), AMOUNT, 0);
        uint256 previewOut = _asSY(sy).previewRedeem(address(stETH), sharesOut);
        uint256 redeemed = _asSY(sy).redeem(user, sharesOut, address(stETH), 0, false);
        vm.stopPrank();

        assertEq(sharesOut, previewShares);
        assertEq(redeemed, previewOut);
        assertEq(redeemed, AMOUNT);
        assertEq(stETH.balanceOf(user), AMOUNT);
        assertEq(wstETH.balanceOf(sy), 0);
        assertEq(_asSY(sy).exchangeRate(), 1e18);
    }

    function testMockL2StEthUsesShareBalancesForTransfersAndTokenAllowances() external {
        MockToken l2WstEth = new MockToken("wstETH", "wstETH", 18);
        MockL2StETH l2StEth = new MockL2StETH(address(l2WstEth), 2 ether);
        address receiver = address(0xCAFE);
        address spender = address(0xD00D);

        l2StEth.mint(user, 5 ether);
        assertEq(l2StEth.balanceOf(user), 10 ether);

        vm.prank(user);
        l2StEth.transfer(receiver, 4 ether);
        assertEq(l2StEth.balanceOf(user), 6 ether);
        assertEq(l2StEth.balanceOf(receiver), 4 ether);

        vm.prank(receiver);
        l2StEth.approve(spender, 2 ether);
        vm.prank(spender);
        l2StEth.transferFrom(receiver, user, 2 ether);

        assertEq(l2StEth.allowance(receiver, spender), 0);
        assertEq(l2StEth.balanceOf(user), 8 ether);
        assertEq(l2StEth.balanceOf(receiver), 2 ether);
    }

    function testVaultBackedAdaptersUseDepositRedeemAndExchangeRate() external {
        MockToken usde = new MockToken("USDe", "USDe", 18);
        MockVault sUSDe = new MockVault(address(usde));
        address ethena = ProxyTestHelper.deploy(
            address(new OutrunStakedUSDeSYUpgradeable()),
            abi.encodeCall(OutrunStakedUSDeSYUpgradeable.initialize, (owner, address(usde), address(sUSDe)))
        );

        usde.mint(user, AMOUNT);
        vm.startPrank(user);
        usde.approve(ethena, AMOUNT);
        uint256 ethenaPreviewShares = _asSY(ethena).previewDeposit(address(usde), AMOUNT);
        uint256 ethenaShares = _asSY(ethena).deposit(user, address(usde), AMOUNT, 0);
        uint256 ethenaPreviewOut = _asSY(ethena).previewRedeem(address(sUSDe), ethenaShares);
        uint256 ethenaRedeemed = _asSY(ethena).redeem(user, ethenaShares, address(sUSDe), 0, false);
        vm.stopPrank();

        assertEq(ethenaShares, ethenaPreviewShares);
        assertEq(ethenaRedeemed, ethenaPreviewOut);
        assertEq(_asSY(ethena).exchangeRate(), 1e18);

        MockToken usds = new MockToken("USDS", "USDS", 18);
        MockVault sUSDS = new MockVault(address(usds));
        address sky = ProxyTestHelper.deploy(
            address(new OutrunStakedUsdsSYUpgradeable()),
            abi.encodeCall(OutrunStakedUsdsSYUpgradeable.initialize, (owner, address(usds), address(sUSDS)))
        );

        usds.mint(user, AMOUNT);
        vm.startPrank(user);
        usds.approve(sky, AMOUNT);
        uint256 skyPreviewShares = _asSY(sky).previewDeposit(address(usds), AMOUNT);
        uint256 skyShares = _asSY(sky).deposit(user, address(usds), AMOUNT, 0);
        uint256 skyPreviewOut = _asSY(sky).previewRedeem(address(usds), skyShares);
        uint256 skyRedeemed = _asSY(sky).redeem(user, skyShares, address(usds), 0, false);
        vm.stopPrank();

        assertEq(skyShares, skyPreviewShares);
        assertEq(skyRedeemed, skyPreviewOut);
        assertEq(skyRedeemed, AMOUNT);
        assertEq(usds.balanceOf(user), AMOUNT);
        assertEq(_asSY(sky).exchangeRate(), 1e18);

        MockToken usdc = new MockToken("USDC", "USDC", 6);
        MockToken l2Usds = new MockToken("USDS", "USDS", 18);
        MockToken l2sUSDS = new MockToken("sUSDS", "sUSDS", 18);
        address skyL2 = ProxyTestHelper.deploy(
            address(new OutrunL2StakedUsdsSYUpgradeable()),
            abi.encodeCall(
                OutrunL2StakedUsdsSYUpgradeable.initialize,
                (owner, address(usdc), address(l2Usds), address(l2sUSDS), address(new MockPSM3()))
            )
        );

        usdc.mint(user, AMOUNT);
        vm.startPrank(user);
        usdc.approve(skyL2, AMOUNT);
        uint256 skyL2PreviewShares = _asSY(skyL2).previewDeposit(address(usdc), AMOUNT);
        uint256 skyL2Shares = _asSY(skyL2).deposit(user, address(usdc), AMOUNT, 0);
        uint256 skyL2PreviewOut = _asSY(skyL2).previewRedeem(address(l2Usds), skyL2Shares);
        uint256 skyL2Redeemed = _asSY(skyL2).redeem(user, skyL2Shares, address(l2Usds), 0, false);
        vm.stopPrank();

        assertEq(skyL2Shares, skyL2PreviewShares);
        assertEq(skyL2Redeemed, skyL2PreviewOut);
        assertEq(skyL2Redeemed, AMOUNT);
        assertEq(l2Usds.balanceOf(user), AMOUNT);
        assertEq(_asSY(skyL2).exchangeRate(), 1e18);
    }

    function testOracleAndBnbFamiliesCoverRoundtripPreviewAndExchangeRate() external {
        address generic = _deployL2Staked();
        _assertYieldTokenRoundtrip(generic, token, AMOUNT);
        assertEq(_asSY(generic).exchangeRate(), 1.2e18);

        address l2Wst = _deployL2WstETH();
        _assertYieldTokenRoundtrip(l2Wst, token, AMOUNT);
        assertEq(_asSY(l2Wst).exchangeRate(), 1.2e18);

        MockToken l2WstEth = new MockToken("wstETH", "wstETH", 18);
        MockL2StETH l2StEth = new MockL2StETH(address(l2WstEth), 2 ether);
        address l2Wrappable = ProxyTestHelper.deploy(
            address(new OutrunL2WrappableWstETHSYUpgradeable()),
            abi.encodeWithSelector(
                OutrunL2WrappableWstETHSYUpgradeable.initialize.selector,
                owner,
                address(l2StEth),
                address(l2WstEth),
                address(l2StEth),
                18
            )
        );

        l2StEth.mint(user, AMOUNT);
        vm.startPrank(user);
        l2StEth.approve(l2Wrappable, AMOUNT);
        uint256 l2PreviewShares = _asSY(l2Wrappable).previewDeposit(address(l2StEth), AMOUNT);
        uint256 l2Shares = _asSY(l2Wrappable).deposit(user, address(l2StEth), AMOUNT, 0);
        uint256 l2PreviewOut = _asSY(l2Wrappable).previewRedeem(address(l2StEth), l2Shares);
        uint256 l2Redeemed = _asSY(l2Wrappable).redeem(user, l2Shares, address(l2StEth), 0, false);
        vm.stopPrank();

        assertEq(l2Shares, l2PreviewShares);
        assertEq(l2Redeemed, l2PreviewOut);
        assertEq(l2Redeemed, AMOUNT);
        assertEq(_asSY(l2Wrappable).exchangeRate(), l2StEth.getTokensByShares(1 ether));

        address lista = _deployLista();
        _assertYieldTokenRoundtrip(lista, token, AMOUNT);
        assertEq(_asSY(lista).previewDeposit(NATIVE, AMOUNT), AMOUNT);
        assertEq(_asSY(lista).exchangeRate(), 1e18);

        address aster = _deployAster();
        _assertYieldTokenRoundtrip(aster, token, AMOUNT);
        assertEq(_asSY(aster).previewDeposit(NATIVE, AMOUNT), AMOUNT);
        assertEq(_asSY(aster).exchangeRate(), 1e18);
    }

    function _assertYieldTokenRoundtrip(address sy, MockToken ybt, uint256 amount) internal {
        uint256 balanceBefore = ybt.balanceOf(user);
        ybt.mint(user, amount);
        vm.startPrank(user);
        ybt.approve(sy, amount);
        uint256 previewShares = _asSY(sy).previewDeposit(address(ybt), amount);
        uint256 sharesOut = _asSY(sy).deposit(user, address(ybt), amount, 0);
        uint256 previewOut = _asSY(sy).previewRedeem(address(ybt), sharesOut);
        uint256 redeemed = _asSY(sy).redeem(user, sharesOut, address(ybt), 0, false);
        vm.stopPrank();

        assertEq(sharesOut, previewShares);
        assertEq(redeemed, previewOut);
        assertEq(redeemed, amount);
        assertEq(ybt.balanceOf(user), balanceBefore + amount);
        assertEq(_asSY(sy).balanceOf(user), 0);
    }

    function _assertSY(address sy, string memory name_, string memory symbol_, address ybt) internal {
        assertEq(_asSY(sy).name(), name_);
        assertEq(_asSY(sy).symbol(), symbol_);
        assertEq(_asSY(sy).yieldBearingToken(), ybt);
        assertEq(_asSY(sy).owner(), owner);
    }

    function _asSY(address sy) internal pure returns (OutrunL2StakedTokenSYUpgradeable) {
        return OutrunL2StakedTokenSYUpgradeable(payable(sy));
    }

    function _storedAddress(address target, bytes32 slot) internal view returns (address) {
        return address(uint160(uint256(vm.load(target, slot))));
    }

    function _erc7201(string memory id) internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(keccak256(bytes(id))) - 1)) & ~bytes32(uint256(0xff));
    }

    function _deployL2Staked() internal returns (address) {
        OutrunL2StakedTokenSYUpgradeable impl = new OutrunL2StakedTokenSYUpgradeable();
        return ProxyTestHelper.deploy(
            address(impl),
            abi.encodeCall(
                OutrunL2StakedTokenSYUpgradeable.initialize,
                ("SY Generic", "SYG", owner, address(token), address(oracle), address(token), 18)
            )
        );
    }

    function _deployWeETH() internal returns (address) {
        OutrunWeETHSYUpgradeable impl = new OutrunWeETHSYUpgradeable();
        MockLiquidityPool pool = new MockLiquidityPool();
        return ProxyTestHelper.deploy(
            address(impl),
            abi.encodeCall(
                OutrunWeETHSYUpgradeable.initialize,
                (owner, address(new MockToken("eETH", "eETH", 18)), address(token), address(0xDAD), address(pool))
            )
        );
    }

    function _deployWstETH() internal returns (address) {
        OutrunWstETHSYUpgradeable impl = new OutrunWstETHSYUpgradeable();
        return ProxyTestHelper.deploy(
            address(impl),
            abi.encodeCall(
                OutrunWstETHSYUpgradeable.initialize,
                (owner, address(new MockToken("stETH", "stETH", 18)), address(token))
            )
        );
    }

    function _deployL2WstETH() internal returns (address) {
        OutrunL2WstETHSYUpgradeable impl = new OutrunL2WstETHSYUpgradeable();
        return ProxyTestHelper.deploy(
            address(impl),
            abi.encodeCall(
                OutrunL2WstETHSYUpgradeable.initialize, (owner, address(token), address(oracle), address(token), 18)
            )
        );
    }

    function _deployL2WrappableWstETH() internal returns (address) {
        OutrunL2WrappableWstETHSYUpgradeable impl = new OutrunL2WrappableWstETHSYUpgradeable();
        return ProxyTestHelper.deploy(
            address(impl),
            abi.encodeWithSelector(
                OutrunL2WrappableWstETHSYUpgradeable.initialize.selector,
                owner,
                address(new MockToken("stETH", "stETH", 18)),
                address(token),
                address(token),
                18
            )
        );
    }

    function _deployEthena() internal returns (address) {
        OutrunStakedUSDeSYUpgradeable impl = new OutrunStakedUSDeSYUpgradeable();
        return ProxyTestHelper.deploy(
            address(impl),
            abi.encodeCall(
                OutrunStakedUSDeSYUpgradeable.initialize,
                (owner, address(new MockToken("USDe", "USDe", 18)), address(token))
            )
        );
    }

    function _deploySky() internal returns (address) {
        OutrunStakedUsdsSYUpgradeable impl = new OutrunStakedUsdsSYUpgradeable();
        return ProxyTestHelper.deploy(
            address(impl),
            abi.encodeCall(
                OutrunStakedUsdsSYUpgradeable.initialize,
                (owner, address(new MockToken("USDS", "USDS", 18)), address(token))
            )
        );
    }

    function _deploySkyL2() internal returns (address) {
        OutrunL2StakedUsdsSYUpgradeable impl = new OutrunL2StakedUsdsSYUpgradeable();
        return ProxyTestHelper.deploy(
            address(impl),
            abi.encodeCall(
                OutrunL2StakedUsdsSYUpgradeable.initialize,
                (
                    owner,
                    address(new MockToken("USDC", "USDC", 6)),
                    address(new MockToken("USDS", "USDS", 18)),
                    address(token),
                    address(new MockPSM3())
                )
            )
        );
    }

    function _deployLista() internal returns (address) {
        OutrunSlisBNBSYUpgradeable impl = new OutrunSlisBNBSYUpgradeable();
        return ProxyTestHelper.deploy(
            address(impl),
            abi.encodeCall(
                OutrunSlisBNBSYUpgradeable.initialize, (owner, address(token), address(new MockListaStakeManager()))
            )
        );
    }

    function _deployAster() internal returns (address) {
        OutrunAsBNBSYUpgradeable impl = new OutrunAsBNBSYUpgradeable();
        MockListaStakeManager stakeManager = new MockListaStakeManager();
        MockYieldProxy yieldProxy = new MockYieldProxy(address(stakeManager));
        MockToken slis = new MockToken("slisBNB", "slisBNB", 18);
        MockAsBnbMinter minter = new MockAsBnbMinter(address(token), address(slis), address(yieldProxy));
        return ProxyTestHelper.deploy(
            address(impl),
            abi.encodeCall(OutrunAsBNBSYUpgradeable.initialize, (owner, address(token), address(slis), address(minter)))
        );
    }
}
