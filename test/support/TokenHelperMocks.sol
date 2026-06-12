// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {TokenHelper} from "../../src/libraries/TokenHelper.sol";
import {IWETH} from "../../src/libraries/IWETH.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// Harness to expose internal functions
contract TokenHelperHarness is TokenHelper {
    constructor() {}

    function exposedTransferIn(address token, address from, uint256 amount) external payable {
        _transferIn(token, from, amount);
    }

    function exposedTransferOut(address token, address to, uint256 amount) external {
        _transferOut(token, to, amount);
    }

    function exposedSafeApprove(address token, address to, uint256 amount) external {
        _safeApprove(token, to, amount);
    }

    function exposedSafeApproveInf(address token, address to) external {
        _safeApproveInf(token, to);
    }

    function exposedSelfBalance(address token) external view returns (uint256) {
        return _selfBalance(token);
    }

    // Receive ETH for native transfers
    receive() external payable {}
}

// Mock ERC20 with mint capability
contract MockERC20 is ERC20 {
    constructor(string memory _name, string memory _symbol, uint8 _decimals) ERC20(_name, _symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// Mock WETH for testing wrap/unwrap
contract MockWETH is IWETH {
    string public name = "Wrapped Ether";
    string public symbol = "WETH";
    uint8 public decimals = 18;
    uint256 public override totalSupply;

    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    function deposit() external payable override {
        balanceOf[msg.sender] += msg.value;
        totalSupply += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint256 wad) external override {
        require(balanceOf[msg.sender] >= wad, "insufficient balance");
        balanceOf[msg.sender] -= wad;
        totalSupply -= wad;
        (bool success,) = msg.sender.call{value: wad}("");
        require(success, "withdraw failed");
        emit Withdrawal(msg.sender, wad);
    }

    function transfer(address to, uint256 value) external override returns (bool) {
        require(balanceOf[msg.sender] >= value, "insufficient balance");
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        emit Transfer(msg.sender, to, value);
        return true;
    }

    function approve(address spender, uint256 value) external override returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external override returns (bool) {
        require(balanceOf[from] >= value, "insufficient balance");
        require(allowance[from][msg.sender] >= value, "insufficient allowance");
        allowance[from][msg.sender] -= value;
        balanceOf[from] -= value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
        return true;
    }

    // solhint-disable-next-line no-complex-fallback
    receive() external payable {
        balanceOf[msg.sender] += msg.value;
        totalSupply += msg.value;
        emit Deposit(msg.sender, msg.value);
    }
}

    // Contract that always reverts in receive()
    contract RevertingReceiver {
        receive() external payable {
            revert("I don't accept ETH");
        }
    }

    // Pausable token for testing OutrunERC20Pausable
    contract PausableToken is ERC20, Pausable, Ownable {
        constructor() ERC20("Pausable Token", "PAUSE") Ownable(msg.sender) {}

        function _update(address from, address to, uint256 value) internal virtual override whenNotPaused {
            super._update(from, to, value);
        }

        function pause() external onlyOwner {
            _pause();
        }

        function unpause() external onlyOwner {
            _unpause();
        }

        function mint(address to, uint256 amount) external {
            _mint(to, amount);
        }
    }
