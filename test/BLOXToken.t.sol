// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {BLOXToken} from "../src/BLOXToken.sol";

/// @dev Test fixture only. Represents the immediate factory deployer.
contract TokenFactoryProbe {
    function deploy(bytes32 salt) external returns (BLOXToken) {
        return new BLOXToken{salt: salt}();
    }

    function move(BLOXToken token, address recipient, uint256 amount) external returns (bool) {
        return token.transfer(recipient, amount);
    }
}

contract BLOXTokenTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;

    BLOXToken private token;
    address private deployer;
    address private alice;
    address private bob;
    address private spender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        deployer = makeAddr("deployer");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
        vm.prank(deployer);
        token = new BLOXToken();
    }

    function test_metadataAndEntireSupplyBelongToDeployer() public view {
        assertEq(token.name(), "BLOX IMD");
        assertEq(token.symbol(), "BLOX");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(deployer, spender), 0);
    }

    function test_constructorEmitsExactlyOneMint() public {
        vm.recordLogs();
        vm.prank(alice);
        BLOXToken fresh = new BLOXToken();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(fresh));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(alice))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
        assertEq(fresh.balanceOf(alice), SUPPLY);
    }

    function test_create2MintsToFactoryAndLaunchTransfersArriveWhole() public {
        TokenFactoryProbe factory = new TokenFactoryProbe();
        bytes32 salt = keccak256("BLOX deployment test");
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), address(factory), salt, keccak256(type(BLOXToken).creationCode))
                    )
                )
            )
        );
        vm.prank(alice, alice);
        BLOXToken launched = factory.deploy(salt);
        assertEq(address(launched), predicted);
        assertEq(launched.balanceOf(address(factory)), SUPPLY);
        assertEq(launched.balanceOf(alice), 0);
        assertEq(launched.balanceOf(address(this)), 0);

        address distributor = makeAddr("launch distributor");
        address poolManager = makeAddr("pool manager");
        address recipient = makeAddr("remainder recipient");
        uint256 swarm = SUPPLY / 10;
        uint256 pool = SUPPLY * 88 / 100;
        uint256 remainder = SUPPLY - swarm - pool;
        assertTrue(factory.move(launched, distributor, swarm));
        assertTrue(factory.move(launched, poolManager, pool));
        assertTrue(factory.move(launched, recipient, remainder));
        assertEq(launched.balanceOf(address(factory)), 0);
        assertEq(launched.balanceOf(distributor), swarm);
        assertEq(launched.balanceOf(poolManager), pool);
        assertEq(launched.balanceOf(recipient), remainder);

        vm.prank(distributor);
        assertTrue(launched.transfer(alice, swarm));
        assertEq(launched.balanceOf(distributor), 0);
        assertEq(launched.balanceOf(alice), swarm);
        // Exercise exact token movements into and out of a pool address.
        vm.prank(poolManager);
        assertTrue(launched.transfer(bob, 25e18));
        assertEq(launched.balanceOf(bob), 25e18);
        vm.prank(bob);
        assertTrue(launched.transfer(poolManager, 25e18));
        assertEq(launched.balanceOf(bob), 0);
        assertEq(launched.balanceOf(poolManager), pool);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function test_transferReturnsTrueAndEmitsExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(deployer, alice, 10e18);
        vm.prank(deployer);
        assertTrue(token.transfer(alice, 10e18));
        assertEq(token.balanceOf(deployer), SUPPLY - 10e18);
        assertEq(token.balanceOf(alice), 10e18);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_entireSupplyCanMove() public {
        vm.prank(deployer);
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
    }

    function test_zeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_selfTransferPreservesBalance() public {
        vm.prank(deployer);
        assertTrue(token.transfer(deployer, SUPPLY));
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferRejectsZeroRecipientEvenForZeroAmount() public {
        vm.startPrank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        vm.stopPrank();
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_emptyAccountCannotTransfer() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        token.transfer(bob, 1);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_approveReplacesAllowanceAndEmitsEvent() public {
        vm.startPrank(deployer);
        assertTrue(token.approve(spender, 100));
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(deployer, spender, 40);
        assertTrue(token.approve(spender, 40));
        vm.stopPrank();
        assertEq(token.allowance(deployer, spender), 40);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_approveRejectsZeroSpender() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.allowance(deployer, address(0)), 0);
    }

    function test_approvalIsScopedToCaller() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, SUPPLY));
        assertEq(token.allowance(alice, spender), SUPPLY);
        assertEq(token.allowance(deployer, spender), 0);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(deployer, bob, 1);
    }

    function test_revokedAllowanceCannotBeSpent() public {
        vm.startPrank(deployer);
        assertTrue(token.approve(spender, 100));
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(deployer, spender, 0);
        assertTrue(token.approve(spender, 0));
        vm.stopPrank();
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(deployer, alice, 1);
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_transferFromSpendsAllowanceAndEmitsTransfer() public {
        vm.prank(deployer);
        assertTrue(token.approve(spender, 100));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(deployer, alice, 40);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, 40));
        assertEq(token.balanceOf(deployer), SUPPLY - 40);
        assertEq(token.balanceOf(alice), 40);
        assertEq(token.allowance(deployer, spender), 60);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_exhaustedAllowanceCannotBeReused() public {
        vm.prank(deployer);
        assertTrue(token.approve(spender, 100));
        vm.startPrank(spender);
        assertTrue(token.transferFrom(deployer, alice, 100));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(deployer, alice, 1);
        vm.stopPrank();
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.balanceOf(alice), 100);
    }

    function test_unapprovedCallerCannotUseAnotherSpendersAllowance() public {
        vm.prank(deployer);
        assertTrue(token.approve(spender, 100));
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        token.transferFrom(deployer, alice, 1);
        assertEq(token.allowance(deployer, spender), 100);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_deployerCannotSpendHolderTokensWithoutApproval() public {
        vm.prank(deployer);
        assertTrue(token.transfer(alice, 100));
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        token.transferFrom(alice, deployer, 1);
        assertEq(token.balanceOf(alice), 100);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 100));
        assertEq(token.balanceOf(bob), 100);
    }

    function test_transferFromInsufficientBalanceRollsBackAllowance() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, 100));
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 100));
        token.transferFrom(alice, bob, 100);
        assertEq(token.allowance(alice, spender), 100);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferFromZeroRecipientRollsBackAllowance() public {
        vm.prank(deployer);
        assertTrue(token.approve(spender, 100));
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(deployer, address(0), 100);
        assertEq(token.allowance(deployer, spender), 100);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromSelfStillConsumesAllowance() public {
        vm.prank(deployer);
        assertTrue(token.approve(spender, 100));
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, deployer, 100));
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.allowance(deployer, spender), 0);
    }

    function test_zeroTransferFromRequiresNoAllowance() public {
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_infiniteAllowanceIsNotDecremented() public {
        vm.prank(deployer);
        assertTrue(token.approve(spender, type(uint256).max));
        vm.startPrank(spender);
        assertTrue(token.transferFrom(deployer, alice, 1));
        assertTrue(token.transferFrom(deployer, bob, SUPPLY - 1));
        vm.stopPrank();
        assertEq(token.allowance(deployer, spender), type(uint256).max);
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice) + token.balanceOf(bob), SUPPLY);
    }

    function test_noAdminMintBurnOrUpgradeEntrypoints() public {
        bytes[] memory calls = new bytes[](18);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", alice, 1);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 1);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("issue(uint256)", 1);
        calls[4] = abi.encodeWithSignature("initialize(address)", alice);
        calls[5] = abi.encodeWithSignature("setMinter(address)", alice);
        calls[6] = abi.encodeWithSignature("setOwner(address)", alice);
        calls[7] = abi.encodeWithSignature("transferOwnership(address)", alice);
        calls[8] = abi.encodeWithSignature("upgradeTo(address)", alice);
        calls[9] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[10] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1);
        calls[11] = abi.encodeWithSignature("pause()");
        calls[12] = abi.encodeWithSignature("unpause()");
        calls[13] = abi.encodeWithSignature("blacklist(address)", alice);
        calls[14] = abi.encodeWithSignature("freeze(address)", alice);
        calls[15] = abi.encodeWithSignature("seize(address)", alice);
        calls[16] = abi.encodeWithSignature("setTransfersEnabled(bool)", false);
        calls[17] = abi.encodeWithSignature("setBlacklist(address,bool)", alice, true);

        vm.prank(deployer);
        assertTrue(token.transfer(alice, 100));
        for (uint256 i; i < calls.length; ++i) {
            vm.prank(deployer);
            (bool fromDeployer,) = address(token).call(calls[i]);
            assertFalse(fromDeployer, "deployer reached an unsupported function");
            vm.prank(bob);
            (bool fromStranger,) = address(token).call(calls[i]);
            assertFalse(fromStranger, "stranger reached an unsupported function");
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(alice), 100);
            assertEq(token.balanceOf(deployer), SUPPLY - 100);
        }
        vm.prank(alice);
        assertTrue(token.transfer(bob, 100));
        assertEq(token.balanceOf(bob), 100);
    }

    function testFuzz_transferPreservesSupply(address recipient, uint256 rawAmount) public {
        vm.assume(recipient != address(0) && recipient != deployer);
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        vm.prank(deployer);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferMoreThanBalanceReverts(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, SUPPLY + 1, type(uint256).max);
        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, amount)
        );
        token.transfer(alice, amount);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_delegatedTransfer(uint256 rawAmount, uint256 rawAllowance) public {
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        uint256 allowance = bound(rawAllowance, amount, type(uint256).max);
        vm.prank(deployer);
        assertTrue(token.approve(spender, allowance));
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, amount));
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.allowance(deployer, spender), allowance == type(uint256).max ? allowance : allowance - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_insufficientAllowanceRevertsWithoutChanges(uint256 rawAllowance, uint256 rawAmount) public {
        uint256 allowance = bound(rawAllowance, 0, SUPPLY - 1);
        uint256 amount = bound(rawAmount, allowance + 1, SUPPLY);
        vm.prank(deployer);
        assertTrue(token.approve(spender, allowance));
        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowance, amount)
        );
        token.transferFrom(deployer, alice, amount);
        assertEq(token.allowance(deployer, spender), allowance);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }
}
