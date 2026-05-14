// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {OutrunL2StakedTokenSYUpgradeable} from "../../src/yield/OutrunL2StakedTokenSYUpgradeable.sol";
import {OutrunL2WstETHSYUpgradeable} from "../../src/yield/adapters/lido/OutrunL2WstETHSYUpgradeable.sol";
import {ProxyTestHelper} from "./helpers/ProxyTestHelper.sol";

interface IOracleBackedSYUpgradeable {
    function exchangeRateOracle() external view returns (address);
    function setExchangeRateOracle(address newOracle) external;
    function exchangeRate() external view returns (uint256);
}

contract OracleSetterMockToken is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}
}

contract OracleSetterMockOracle {
    uint256 internal rate;

    constructor(uint256 rate_) {
        rate = rate_;
    }

    function getExchangeRate() external view returns (uint256) {
        return rate;
    }
}

contract RevertingOracle {
    function getExchangeRate() external pure returns (uint256) {
        revert("ORACLE_DOWN");
    }
}

contract OracleSetterUpgradeableTest is Test {
    event SetExchangeRateOracle(address indexed oldOracle, address indexed newOracle);

    address internal owner = address(0xA11CE);
    address internal nonOwner = address(0xB0B);

    OracleSetterMockToken internal token;
    OracleSetterMockOracle internal oracle;

    function setUp() external {
        token = new OracleSetterMockToken("Yield Token", "YBT");
        oracle = new OracleSetterMockOracle(1.1e18);
    }

    function testL2StakedTokenOwnerCanSetExchangeRateOracle() external {
        IOracleBackedSYUpgradeable sy = _deployL2Staked();
        OracleSetterMockOracle newOracle = new OracleSetterMockOracle(1.2e18);

        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit SetExchangeRateOracle(address(oracle), address(newOracle));
        sy.setExchangeRateOracle(address(newOracle));

        assertEq(sy.exchangeRateOracle(), address(newOracle));
    }

    function testL2WstEthOwnerCanSetExchangeRateOracle() external {
        IOracleBackedSYUpgradeable sy = _deployL2WstETH();
        OracleSetterMockOracle newOracle = new OracleSetterMockOracle(1.2e18);

        vm.prank(owner);
        sy.setExchangeRateOracle(address(newOracle));

        assertEq(sy.exchangeRateOracle(), address(newOracle));
    }

    function testNonOwnerCannotSetExchangeRateOracle() external {
        IOracleBackedSYUpgradeable sy = _deployL2Staked();
        OracleSetterMockOracle newOracle = new OracleSetterMockOracle(1.2e18);
        vm.prank(nonOwner);
        vm.expectRevert();
        sy.setExchangeRateOracle(address(newOracle));
    }

    function testZeroExchangeRateOracleReverts() external {
        IOracleBackedSYUpgradeable sy = _deployL2Staked();
        vm.prank(owner);
        vm.expectRevert();
        sy.setExchangeRateOracle(address(0));
    }

    function testExchangeRateReflectsUpdatedOracle() external {
        IOracleBackedSYUpgradeable sy = _deployL2Staked();
        assertEq(sy.exchangeRate(), 1.1e18);

        OracleSetterMockOracle newOracle = new OracleSetterMockOracle(1.7e18);
        vm.prank(owner);
        sy.setExchangeRateOracle(address(newOracle));

        assertEq(sy.exchangeRate(), 1.7e18);
    }

    function testSetterDoesNotCallOracleDuringUpdate() external {
        IOracleBackedSYUpgradeable sy = _deployL2Staked();
        RevertingOracle newOracle = new RevertingOracle();

        vm.prank(owner);
        sy.setExchangeRateOracle(address(newOracle));

        assertEq(sy.exchangeRateOracle(), address(newOracle));
        vm.expectRevert("ORACLE_DOWN");
        sy.exchangeRate();
    }

    function _deployL2Staked() internal returns (IOracleBackedSYUpgradeable) {
        OutrunL2StakedTokenSYUpgradeable implementation = new OutrunL2StakedTokenSYUpgradeable();
        return IOracleBackedSYUpgradeable(
            payable(ProxyTestHelper.deploy(
                    address(implementation),
                    abi.encodeCall(
                        OutrunL2StakedTokenSYUpgradeable.initialize,
                        ("SY Generic", "SYG", owner, address(token), address(oracle), address(token), 18)
                    )
                ))
        );
    }

    function _deployL2WstETH() internal returns (IOracleBackedSYUpgradeable) {
        OutrunL2WstETHSYUpgradeable implementation = new OutrunL2WstETHSYUpgradeable();
        return IOracleBackedSYUpgradeable(
            payable(ProxyTestHelper.deploy(
                    address(implementation),
                    abi.encodeCall(
                        OutrunL2WstETHSYUpgradeable.initialize,
                        (owner, address(token), address(oracle), address(token), 18)
                    )
                ))
        );
    }
}
