// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract ZKSP is ERC20, Pausable, AccessControl {
    error MaxSupplyReached();
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant ADMIN = keccak256("ADMIN");

    uint256 public _maxSupply = 60_000_000_000e18;

    constructor(address _admin, address _pauser, address _minter) ERC20("zkSwap", "ZKSP") {
        _setRoleAdmin(DEFAULT_ADMIN_ROLE, ADMIN);
        _grantRole(ADMIN, _admin);

        _setRoleAdmin(PAUSER_ROLE, ADMIN);
        _grantRole(PAUSER_ROLE, _pauser);

        _setRoleAdmin(MINTER_ROLE, ADMIN);
        _grantRole(MINTER_ROLE, _minter);
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        if (totalSupply() + amount > _maxSupply) revert MaxSupplyReached();

        _mint(to, amount);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override whenNotPaused {
        super._beforeTokenTransfer(from, to, amount);
    }
}
