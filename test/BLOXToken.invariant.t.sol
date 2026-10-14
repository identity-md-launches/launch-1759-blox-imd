// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
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

    function move(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) public {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = bound(amountSeed, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function allow(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) public {
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

    function moveAll(uint256 fromSeed, uint256 toSeed) external {
        move(fromSeed, toSeed, expectedBalance[actors[fromSeed % actors.length]]);
    }

    /// @dev Reach revocation and unlimited approval deliberately, between ordinary approvals and spends.
    function allowEdge(uint256 ownerSeed, uint256 spenderSeed, bool unlimited) external {
        allow(ownerSeed, spenderSeed, unlimited ? type(uint256).max : 0);
    }

    function rejectOverBalance(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        token.transfer(to, amount);
        // No ghost update: the invariants must still match every balance and allowance.
    }

    function rejectOverspend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowance = expectedAllowance[owner][spender];
        uint256 amount;
        bytes memory reason;
        if (allowance == type(uint256).max) {
            // Infinite authorization still cannot spend more than the owner's balance.
            uint256 balance = expectedBalance[owner];
            amount = bound(amountSeed, balance + 1, type(uint256).max);
            reason = abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount);
        } else {
            amount = bound(amountSeed, allowance + 1, type(uint256).max);
            reason =
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowance, amount);
        }
        vm.prank(spender);
        vm.expectRevert(reason);
        token.transferFrom(owner, to, amount);
    }

    function rejectSpendOverBalance(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 amountSeed,
        bool unlimited
    ) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[owner];
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        // Ensure authorization succeeds so this exercises rollback after allowance spending.
        allow(ownerSeed, spenderSeed, unlimited ? type(uint256).max : amount);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        token.transferFrom(owner, to, amount);
    }

    function rejectZeroRecipient(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, bool delegated) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 available = expectedBalance[owner];
        uint256 allowance = expectedAllowance[owner][spender];
        if (delegated && allowance < available) available = allowance;
        uint256 amount = bound(amountSeed, 0, available);
        vm.prank(delegated ? spender : owner);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        if (delegated) token.transferFrom(owner, address(0), amount);
        else token.transfer(address(0), amount);
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), amount);
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
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

        // Start with funded holders and usable approvals. All setup uses the real public API.
        for (uint256 i = 1; i < actors.length; ++i) {
            handler.move(0, i, SUPPLY / actors.length);
        }
        for (uint256 i; i < actors.length; ++i) {
            handler.allow(i, (i + 1) % actors.length, SUPPLY / actors.length);
        }

        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = BLOXHandler.move.selector;
        selectors[1] = BLOXHandler.allow.selector;
        selectors[2] = BLOXHandler.spend.selector;
        selectors[3] = BLOXHandler.moveAll.selector;
        selectors[4] = BLOXHandler.allowEdge.selector;
        selectors[5] = BLOXHandler.rejectOverBalance.selector;
        selectors[6] = BLOXHandler.rejectOverspend.selector;
        selectors[7] = BLOXHandler.rejectSpendOverBalance.selector;
        selectors[8] = BLOXHandler.rejectZeroRecipient.selector;
        selectors[9] = BLOXHandler.rejectZeroSpender.selector;
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
            assertEq(token.allowance(actors[i], address(0)), 0);
            assertEq(token.allowance(address(0), actors[i]), 0);
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actors[i], actors[j]), handler.expectedAllowance(actors[i], actors[j]));
            }
        }
    }

    function invariant_metadataNeverChanges() public view {
        assertEq(token.name(), "BLOX IMD");
        assertEq(token.symbol(), "BLOX");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
    }

    /// @dev After every campaign, each holder can move its entire remaining balance.
    function afterInvariant() public {
        for (uint256 i = 1; i < actors.length; ++i) {
            handler.move(i, 0, handler.expectedBalance(actors[i]));
            assertEq(token.balanceOf(actors[i]), 0);
        }
        assertEq(token.balanceOf(actors[0]), SUPPLY);
        invariant_supplyAndEveryBalanceAreConserved();
        invariant_onlyApprovedAllowancesCanBeSpent();
    }
}
