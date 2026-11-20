// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title MockERC20
/// @notice Testnet token with a 24h faucet.
contract MockERC20 is ERC20, Ownable {
    uint8 private immutable _decimals;
    uint256 public immutable faucetAmount;
    uint256 public constant FAUCET_COOLDOWN = 24 hours;

    mapping(address => uint256) public lastFaucet;

    event Faucet(address indexed to, uint256 amount);

    error FaucetCooldown(uint256 availableAt);

    constructor(string memory name_, string memory symbol_, uint8 decimals_, uint256 faucetAmount_)
        ERC20(name_, symbol_)
        Ownable(msg.sender)
    {
        _decimals = decimals_;
        faucetAmount = faucetAmount_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function faucet() external {
        uint256 last = lastFaucet[msg.sender];
        if (last != 0 && block.timestamp < last + FAUCET_COOLDOWN) revert FaucetCooldown(last + FAUCET_COOLDOWN);
        lastFaucet[msg.sender] = block.timestamp;
        _mint(msg.sender, faucetAmount);
        emit Faucet(msg.sender, faucetAmount);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function faucetAvailableIn(address account) external view returns (uint256) {
        uint256 last = lastFaucet[account];
        if (last == 0 || block.timestamp >= last + FAUCET_COOLDOWN) return 0;
        return last + FAUCET_COOLDOWN - block.timestamp;
    }
}
