// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title BLOX IMD
/// @notice A fixed-supply ERC-20 with 18 decimals and exact, untaxed transfers.
/// @dev The immediate deployer receives the entire supply. In the launch flow this
/// is the factory. There are no external mint, burn, admin, or upgrade functions.
contract BLOXToken is ERC20 {
    /// @notice One billion BLOX expressed in the token's smallest units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("BLOX IMD", "BLOX") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
