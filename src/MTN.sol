// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "solmate/tokens/ERC20.sol";

// Simple mintable ERC20: METANA (MTN)
contract MTN is ERC20 {
    constructor() ERC20("METANA", "MTN", 18) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

