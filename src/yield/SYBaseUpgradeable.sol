// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {NativeAmountMismatch} from "../libraries/CommonErrors.sol";
import {TokenHelper} from "../libraries/TokenHelper.sol";
import {IStandardizedYield} from "./interfaces/IStandardizedYield.sol";
import {OutrunERC20PausableUpgradeable} from "../assets/base/OutrunERC20PausableUpgradeable.sol";

abstract contract SYBaseUpgradeable is
    IStandardizedYield,
    OutrunERC20PausableUpgradeable,
    TokenHelper,
    UUPSUpgradeable
{
    /// @custom:storage-location erc7201:outrun.storage.SYBase
    // forge-lint: disable-next-line(pascal-case-struct)
    struct SYBaseStorage {
        address yieldBearingToken;
    }

    // keccak256(abi.encode(uint256(keccak256("outrun.storage.SYBase")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant SY_BASE_STORAGE_LOCATION =
        0x47ee1d05b1829703ec3dd61a22c784c3e0b2d5dbffb0a55782381dabc9c3eb00;

    constructor() {
        _disableInitializers();
    }

    receive() external payable {}

    function __SYBase_init(string memory name_, string memory symbol_, address yieldBearingToken_, address owner_)
        internal
        onlyInitializing
    {
        require(yieldBearingToken_ != address(0), SYZeroAddress());
        __UUPSUpgradeable_init();
        __OutrunERC20Pausable_init(name_, symbol_, IERC20Metadata(yieldBearingToken_).decimals(), owner_);
        _getSYBaseStorage().yieldBearingToken = yieldBearingToken_;
    }

    function _getSYBaseStorage() private pure returns (SYBaseStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := SY_BASE_STORAGE_LOCATION
        }
    }

    function yieldBearingToken() public view returns (address) {
        return _getSYBaseStorage().yieldBearingToken;
    }

    function deposit(address receiver, address tokenIn, uint256 amountTokenToDeposit, uint256 minSharesOut)
        external
        payable
        nonReentrant
        whenNotPaused
        returns (uint256 amountSharesOut)
    {
        require(isValidTokenIn(tokenIn), SYInvalidTokenIn(tokenIn));
        require(amountTokenToDeposit != 0, SYZeroDeposit());
        if (tokenIn != NATIVE && msg.value != 0) revert NativeAmountMismatch();

        _transferIn(tokenIn, msg.sender, amountTokenToDeposit);

        amountSharesOut = _deposit(tokenIn, amountTokenToDeposit);
        require(amountSharesOut >= minSharesOut, SYInsufficientSharesOut(amountSharesOut, minSharesOut));

        _mint(receiver, amountSharesOut);
        emit Deposit(msg.sender, receiver, tokenIn, amountTokenToDeposit, amountSharesOut);
    }

    function redeem(
        address receiver,
        uint256 amountSharesToRedeem,
        address tokenOut,
        uint256 minTokenOut,
        bool burnFromInternalBalance
    ) external nonReentrant whenNotPaused returns (uint256 amountTokenOut) {
        require(isValidTokenOut(tokenOut), SYInvalidTokenOut(tokenOut));
        require(amountSharesToRedeem != 0, SYZeroRedeem());
        amountTokenOut = _redeem(receiver, tokenOut, amountSharesToRedeem);

        if (burnFromInternalBalance) {
            _burn(address(this), amountSharesToRedeem);
        } else {
            _burn(msg.sender, amountSharesToRedeem);
        }

        require(amountTokenOut >= minTokenOut, SYInsufficientTokenOut(amountTokenOut, minTokenOut));

        emit Redeem(msg.sender, receiver, tokenOut, amountSharesToRedeem, amountTokenOut);
    }

    function _deposit(address tokenIn, uint256 amountDeposited) internal virtual returns (uint256 amountSharesOut);

    function _redeem(address receiver, address tokenOut, uint256 amountSharesToRedeem)
        internal
        virtual
        returns (uint256 amountTokenOut);

    function exchangeRate() external view virtual override returns (uint256 res);

    function previewDeposit(address tokenIn, uint256 amountTokenToDeposit)
        external
        view
        virtual
        returns (uint256 amountSharesOut)
    {
        require(isValidTokenIn(tokenIn), SYInvalidTokenIn(tokenIn));
        return _previewDeposit(tokenIn, amountTokenToDeposit);
    }

    function previewRedeem(address tokenOut, uint256 amountSharesToRedeem)
        external
        view
        virtual
        returns (uint256 amountTokenOut)
    {
        require(isValidTokenOut(tokenOut), SYInvalidTokenOut(tokenOut));
        return _previewRedeem(tokenOut, amountSharesToRedeem);
    }

    function _previewDeposit(address tokenIn, uint256 amountTokenToDeposit)
        internal
        view
        virtual
        returns (uint256 amountSharesOut);

    function _previewRedeem(address tokenOut, uint256 amountSharesToRedeem)
        internal
        view
        virtual
        returns (uint256 amountTokenOut);

    function getTokensIn() public view virtual returns (address[] memory res);

    function getTokensOut() public view virtual returns (address[] memory res);

    function isValidTokenIn(address token) public view virtual returns (bool);

    function isValidTokenOut(address token) public view virtual returns (bool);

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
