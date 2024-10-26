// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20FlashMint.sol";

/// @custom:security-contact admin@syntralink.net

contract SyntraCoin is
    ERC20,
    ERC20Burnable,
    ERC20Pausable,
    Ownable,
    ERC20Permit,
    ERC20FlashMint
{
    constructor(
        address initialOwner,
        uint mintAmount
    )
        ERC20("SyntraCoin", "SNC")
        ERC20Permit("SyntraCoin")
        Ownable(initialOwner)
    {
        _mint(msg.sender, mintAmount);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20, ERC20Pausable) {
        super._update(from, to, value);
    }
}
