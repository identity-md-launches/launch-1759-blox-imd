// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {BLOXToken} from "../src/BLOXToken.sol";

/// @dev Generates transfer/approval histories across a closed set of holders.
/// Balances are modeled independently; the token's getters do not determine the
/// expected balances or allowances. All supply enters via the real constructor.
contract BLOXHandler is Test {
    BLOXToken private immutable token;
    address[4] private actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(BLOXToken token_, address[4] memory actors_, uint256 supply) {
        token = token_;
        actors = actors_;
        expectedBalance[actors_[0]] = supply;
    }

    function move(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = bound(amountSeed, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function allow(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function spend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowance = expectedAllowance[owner][spender];
        uint256 available = expectedBalance[owner] < allowance ? expectedBalance[owner] : allowance;
        uint256 amount = bound(amountSeed, 0, available);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
        if (allowance != type(uint256).max) {
            expectedAllowance[owner][spender] -= amount;
        }
    }
}

contract BLOXTokenInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    BLOXToken private token;
    BLOXHandler private handler;
    address[4] private actors;

    function setUp() public {
        actors = [makeAddr("holder 0"), makeAddr("holder 1"), makeAddr("holder 2"), makeAddr("holder 3")];
        vm.prank(actors[0]);
        token = new BLOXToken();
        handler = new BLOXHandler(token, actors, SUPPLY);

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = BLOXHandler.move.selector;
        selectors[1] = BLOXHandler.allow.selector;
        selectors[2] = BLOXHandler.spend.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_supplyAndEveryBalanceAreConserved() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            uint256 balance = token.balanceOf(actors[i]);
            assertEq(balance, handler.expectedBalance(actors[i]));
            sum += balance;
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function invariant_onlyApprovedAllowancesCanBeSpent() public view {
        for (uint256 i; i < actors.length; ++i) {
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actors[i], actors[j]), handler.expectedAllowance(actors[i], actors[j]));
            }
        }
    }
}
