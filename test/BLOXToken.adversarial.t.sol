// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {BLOXToken} from "src/BLOXToken.sol";

contract BLOXSpenderProbe {
    function pull(BLOXToken token, address from, address to, uint256 amount) external returns (bool) {
        return token.transferFrom(from, to, amount);
    }
}

/// @dev Complements the existing deployment/ERC-20 suite with boundary cases and recovery sequences.
/// forge-config: default.fuzz.runs = 1000
contract BLOXTokenAdversarialTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    BLOXToken private token;
    address private deployer;
    address private alice;
    address private bob;
    address private spender;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        deployer = makeAddr("adversarial deployer");
        alice = makeAddr("adversarial alice");
        bob = makeAddr("adversarial bob");
        spender = makeAddr("adversarial spender");
        vm.prank(deployer);
        token = new BLOXToken();
    }

    function test_oneWeiRoundTripRestoresTheEntireSupply() public {
        vm.prank(deployer);
        assertTrue(token.transfer(alice, 1));
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(deployer), SUPPLY - 1);
        vm.prank(alice);
        assertTrue(token.transfer(deployer, 1));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumTransferRevertsWithoutArithmeticPanic() public {
        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, type(uint256).max)
        );
        token.transfer(alice, type(uint256).max);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_selfTransferAboveBalanceStillReverts() public {
        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, SUPPLY + 1)
        );
        token.transfer(deployer, SUPPLY + 1);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ownerUsingTransferFromNeedsItsOwnApproval() public {
        vm.startPrank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        token.transferFrom(deployer, alice, 1);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);

        assertTrue(token.approve(deployer, 1));
        assertTrue(token.transferFrom(deployer, alice, 1));
        vm.stopPrank();
        assertEq(token.allowance(deployer, deployer), 0);
        assertEq(token.balanceOf(deployer), SUPPLY - 1);
        assertEq(token.balanceOf(alice), 1);
    }

    function test_spenderCanReceiveTheEntireApprovedSupply() public {
        vm.prank(deployer);
        assertTrue(token.approve(spender, SUPPLY));
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, spender, SUPPLY));
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(spender), SUPPLY);
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_largestFiniteApprovalIsDecremented() public {
        uint256 allowance = type(uint256).max - 1;
        vm.prank(deployer);
        assertTrue(token.approve(spender, allowance));
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, 1));
        assertEq(token.allowance(deployer, spender), allowance - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, bob, SUPPLY - 1));
        assertEq(token.allowance(deployer, spender), allowance - SUPPLY);
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_unlimitedApprovalCanBeReducedThenRevoked() public {
        vm.prank(deployer);
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, 1));
        vm.prank(deployer);
        assertTrue(token.approve(spender, 2));
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 2, 3));
        token.transferFrom(deployer, bob, 3);
        assertEq(token.allowance(deployer, spender), 2);
        assertEq(token.balanceOf(bob), 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, bob, 1));
        assertEq(token.allowance(deployer, spender), 1);
        vm.prank(deployer);
        assertTrue(token.approve(spender, 0));
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(deployer, bob, 1);
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.balanceOf(deployer), SUPPLY - 2);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroDelegatedTransferEmitsEventAndPreservesApproval() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 1);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroDelegatedTransferStillRejectsZeroRecipient() public {
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(deployer, address(0), 0);
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroAddressCannotBeUsedAsAMintSource() public {
        // Error precedence is immaterial here: neither zero nor positive amounts may succeed.
        vm.startPrank(spender);
        vm.expectRevert();
        token.transferFrom(address(0), alice, 0);
        vm.expectRevert();
        token.transferFrom(address(0), alice, 1);
        vm.stopPrank();
        assertEq(token.allowance(address(0), spender), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroApprovalStillRejectsZeroSpender() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(deployer, address(0)), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_contractSpenderCannotBorrowItsCallersApproval() public {
        BLOXSpenderProbe relay = new BLOXSpenderProbe();
        vm.prank(deployer);
        assertTrue(token.approve(alice, 10));
        vm.prank(alice, alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(relay), 0, 10));
        relay.pull(token, deployer, bob, 10);
        assertEq(token.allowance(deployer, alice), 10);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(bob), 0);

        vm.prank(deployer);
        assertTrue(token.approve(address(relay), 10));
        vm.prank(alice, alice);
        assertTrue(relay.pull(token, deployer, bob, 10));
        assertEq(token.allowance(deployer, address(relay)), 0);
        assertEq(token.allowance(deployer, alice), 10);
        assertEq(token.balanceOf(deployer), SUPPLY - 10);
        assertEq(token.balanceOf(bob), 10);
    }

    function test_tokensSentToTokenContractRemainPartOfSupply() public {
        vm.prank(deployer);
        assertTrue(token.transfer(address(token), SUPPLY));
        assertEq(token.balanceOf(address(token)), SUPPLY);
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_failedSpendPreservesApprovalAndCanBeRetried(
        uint256 amountSeed,
        uint256 fundedSeed,
        bool unlimited
    ) public {
        uint256 amount = bound(amountSeed, 1, SUPPLY);
        uint256 funded = bound(fundedSeed, 0, amount - 1);
        uint256 approval = unlimited ? type(uint256).max : amount;
        vm.prank(deployer);
        assertTrue(token.transfer(alice, funded));
        vm.prank(alice);
        assertTrue(token.approve(spender, approval));
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, funded, amount));
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), approval);
        assertEq(token.balanceOf(alice), funded);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(deployer), SUPPLY - funded);

        // The original authorization must remain usable once the missing balance arrives.
        vm.prank(deployer);
        assertTrue(token.transfer(alice, amount - funded));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, amount));
        assertEq(token.allowance(alice, spender), unlimited ? type(uint256).max : 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferRoundTripWithExistingBalances(uint256 balanceSeed, uint256 amountSeed) public {
        uint256 aliceBalance = bound(balanceSeed, 1, SUPPLY);
        uint256 bobBalance = SUPPLY - aliceBalance;
        vm.startPrank(deployer);
        assertTrue(token.transfer(alice, aliceBalance));
        assertTrue(token.transfer(bob, bobBalance));
        vm.stopPrank();
        uint256 amount = bound(amountSeed, 1, aliceBalance);
        vm.prank(alice);
        assertTrue(token.transfer(bob, amount));
        assertEq(token.balanceOf(alice), aliceBalance - amount);
        assertEq(token.balanceOf(bob), bobBalance + amount);
        vm.prank(bob);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), aliceBalance);
        assertEq(token.balanceOf(bob), bobBalance);
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_splitDelegatedTransfersMatchOneDirectTransfer(uint256 amountSeed, uint256 splitSeed) public {
        uint256 amount = bound(amountSeed, 1, SUPPLY);
        uint256 first = bound(splitSeed, 0, amount);
        vm.prank(deployer);
        BLOXToken direct = new BLOXToken();
        vm.startPrank(deployer);
        assertTrue(direct.transfer(alice, amount));
        assertTrue(token.approve(spender, amount));
        vm.stopPrank();
        vm.startPrank(spender);
        assertTrue(token.transferFrom(deployer, alice, first));
        assertEq(token.allowance(deployer, spender), amount - first);
        assertTrue(token.transferFrom(deployer, alice, amount - first));
        vm.stopPrank();
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.balanceOf(deployer), direct.balanceOf(deployer));
        assertEq(token.balanceOf(alice), direct.balanceOf(alice));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(deployer) + token.balanceOf(alice), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_approvalReplacementAfterPartialSpend(uint256 spentSeed, uint256 replacementSeed) public {
        uint256 spent = bound(spentSeed, 1, SUPPLY - 1);
        uint256 replacement = bound(replacementSeed, 0, SUPPLY - spent);
        vm.prank(deployer);
        assertTrue(token.approve(spender, SUPPLY));
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, spent));
        vm.prank(deployer);
        assertTrue(token.approve(spender, replacement));
        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, spender, replacement, replacement + 1
            )
        );
        token.transferFrom(deployer, bob, replacement + 1);
        assertEq(token.allowance(deployer, spender), replacement);
        assertEq(token.balanceOf(bob), 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, bob, replacement));
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.balanceOf(alice), spent);
        assertEq(token.balanceOf(bob), replacement);
        assertEq(token.balanceOf(deployer), SUPPLY - spent - replacement);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
