// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    MessagingFee,
    MessagingParams
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

import {OutrunUniversalAssets} from "../../src/assets/base/OutrunUniversalAssets.sol";
import {IUniversalAssets} from "../../src/assets/interfaces/IUniversalAssets.sol";

error AmountSDOverflowed(uint256 amountSD);

contract MockLzEndpoint {
    address internal delegate;
    uint256 internal quoteNativeFee;

    function setDelegate(address delegate_) external {
        delegate = delegate_;
    }

    function setQuoteNativeFee(uint256 nativeFee_) external {
        quoteNativeFee = nativeFee_;
    }

    function quote(MessagingParams calldata, address) external view returns (MessagingFee memory fee) {
        fee = MessagingFee({nativeFee: quoteNativeFee, lzTokenFee: 0});
    }
}

contract MockFlashBorrower is IERC3156FlashBorrower {
    bytes32 internal constant RETURN_VALUE = keccak256("ERC3156FlashBorrower.onFlashLoan");

    OutrunUniversalAssets internal immutable token;
    bool internal shouldApprove;

    constructor(OutrunUniversalAssets token_) {
        token = token_;
    }

    function setShouldApprove(bool value) external {
        shouldApprove = value;
    }

    function onFlashLoan(address, address, uint256 amount, uint256 fee, bytes calldata) external returns (bytes32) {
        if (shouldApprove) {
            token.approve(address(token), amount + fee);
        }
        return RETURN_VALUE;
    }
}

contract OutrunUniversalAssetsTest is Test {
    OutrunUniversalAssets internal uAsset;
    MockLzEndpoint internal endpoint;
    MockFlashBorrower internal borrower;

    address internal owner = address(0xA11CE);
    address internal minter = address(0xB0B);
    address internal receiver = address(0xCAFE);
    address internal flashFeeReceiver = address(0xFEE);

    function setUp() external {
        endpoint = new MockLzEndpoint();
        uAsset = new OutrunUniversalAssets("Outrun UAsset", "UAsset", 18, address(endpoint), owner, address(0));
        borrower = new MockFlashBorrower(uAsset);

        vm.prank(owner);
        uAsset.setPeer(101, bytes32(uint256(uint160(address(0xBEEF)))));
    }

    function testSetMintingCapControlsMintability() external {
        vm.prank(owner);
        uAsset.setMintingCap(minter, 100e18);

        assertEq(uAsset.checkMintableAmount(minter), 100e18);

        vm.prank(minter);
        uAsset.mint(receiver, 40e18);

        assertEq(uAsset.checkMintableAmount(minter), 60e18);
        assertEq(uAsset.balanceOf(receiver), 40e18);
    }

    function testRevokeMinterStopsFurtherMinting() external {
        vm.prank(owner);
        uAsset.setMintingCap(minter, 100e18);

        vm.prank(minter);
        uAsset.mint(receiver, 40e18);

        vm.prank(owner);
        uAsset.revokeMinter(minter);

        assertEq(uAsset.checkMintableAmount(minter), 0);

        vm.prank(minter);
        vm.expectRevert(IUniversalAssets.ReachMintCap.selector);
        uAsset.mint(receiver, 1);
    }

    function testRepayBurnsBalanceAndRestoresMintHeadroom() external {
        vm.prank(owner);
        uAsset.setMintingCap(minter, 100e18);

        vm.prank(minter);
        uAsset.mint(receiver, 40e18);

        vm.prank(receiver);
        uAsset.approve(minter, 15e18);

        vm.prank(minter);
        uAsset.repay(receiver, 15e18);

        assertEq(uAsset.balanceOf(receiver), 25e18);
        assertEq(uAsset.totalSupply(), 25e18);
        assertEq(uAsset.checkMintableAmount(minter), 75e18);
    }

    function testSingleArgumentBurnEntryPointIsRemoved() external {
        vm.prank(owner);
        uAsset.setMintingCap(minter, 100e18);

        vm.prank(minter);
        uAsset.mint(receiver, 10e18);

        vm.prank(receiver);
        // solhint-disable-next-line avoid-low-level-calls
        (bool ok,) = address(uAsset).call(abi.encodeWithSignature("burn(uint256)", 1e18));

        assertFalse(ok);
        assertEq(uAsset.balanceOf(receiver), 10e18);
        assertEq(uAsset.totalSupply(), 10e18);
        assertEq(uAsset.checkMintableAmount(minter), 90e18);
    }

    function testFlashLoanRevertsWithoutAllowanceApproval() external {
        borrower.setShouldApprove(false);

        vm.expectRevert();
        uAsset.flashLoan(borrower, address(uAsset), 100e18, "");
    }

    function testFlashLoanBurnsFeeWhenReceiverUnset() external {
        uint256 amount = 100e18;
        uint256 fee = uAsset.flashFee(address(uAsset), amount);

        borrower.setShouldApprove(true);

        vm.prank(owner);
        uAsset.setMintingCap(owner, fee);

        vm.prank(owner);
        uAsset.mint(address(borrower), fee);

        assertEq(uAsset.totalSupply(), fee);

        uAsset.flashLoan(borrower, address(uAsset), amount, "");

        assertEq(uAsset.flashFeeReceiver(), address(0));
        assertEq(uAsset.totalSupply(), 0);
        assertEq(uAsset.balanceOf(address(borrower)), 0);
    }

    function testFlashLoanTransfersFeeToConfiguredReceiver() external {
        uint256 amount = 100e18;
        uint256 fee = uAsset.flashFee(address(uAsset), amount);

        borrower.setShouldApprove(true);

        vm.prank(owner);
        uAsset.setMintingCap(owner, fee);

        vm.prank(owner);
        uAsset.mint(address(borrower), fee);

        vm.prank(owner);
        uAsset.setFlashFeeReceiver(flashFeeReceiver);

        uAsset.flashLoan(borrower, address(uAsset), amount, "");

        assertEq(uAsset.totalSupply(), fee);
        assertEq(uAsset.balanceOf(address(borrower)), 0);
        assertEq(uAsset.balanceOf(flashFeeReceiver), fee);
    }

    function testConstructorInitializesFlashFeeReceiver() external {
        OutrunUniversalAssets configured =
            new OutrunUniversalAssets("Outrun UAsset", "UAsset", 18, address(endpoint), owner, flashFeeReceiver);

        assertEq(configured.flashFeeReceiver(), flashFeeReceiver);
    }

    function testSetFlashFeeReceiverOnlyOwner() external {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, receiver));
        vm.prank(receiver);
        uAsset.setFlashFeeReceiver(flashFeeReceiver);

        vm.prank(owner);
        uAsset.setFlashFeeReceiver(flashFeeReceiver);

        assertEq(uAsset.flashFeeReceiver(), flashFeeReceiver);
    }

    function testQuoteSendRevertsWhenAmountSDOverflows() external {
        endpoint.setQuoteNativeFee(0.1 ether);

        uint256 overflowAmountLD = (uint256(type(uint64).max) + 1) * uAsset.decimalConversionRate();
        SendParam memory sendParam = SendParam({
            dstEid: 101,
            to: bytes32(uint256(uint160(address(0xBEEF)))),
            amountLD: overflowAmountLD,
            minAmountLD: 0,
            extraOptions: bytes("opts"),
            composeMsg: bytes(""),
            oftCmd: bytes("")
        });

        vm.expectRevert(abi.encodeWithSelector(AmountSDOverflowed.selector, uint256(type(uint64).max) + 1));
        uAsset.quoteSend(sendParam, false);
    }
}
