// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {DIDRegistry} from "../src/DIDRegistry.sol";
import {RecoveryModule} from "../src/RecoveryModule.sol";
import {DelegationRegistry} from "../src/DelegationRegistry.sol";
import {DIDControlled} from "../src/DIDControlled.sol";

contract IdentityLayerTest is Test {
    DIDRegistry did;
    RecoveryModule recovery;
    DelegationRegistry delegation;

    address alice = makeAddr("alice");
    address newKey = makeAddr("newKey");
    address agent = makeAddr("agent");
    address g1 = makeAddr("g1");
    address g2 = makeAddr("g2");
    address g3 = makeAddr("g3");

    bytes32 constant SIG_AUTH = keccak256("sigAuth");
    bytes32 constant SCOPE = keccak256("present:kyc");

    function setUp() public {
        did = new DIDRegistry();
        recovery = new RecoveryModule(did);
        delegation = new DelegationRegistry(did);
    }

    // ---- DIDRegistry ----

    function test_DefaultOwnerIsSelf() public view {
        assertEq(did.identityOwner(alice), alice);
    }

    function test_ChangeOwner() public {
        vm.prank(alice);
        did.changeOwner(alice, newKey);
        assertEq(did.identityOwner(alice), newKey);
        // old key lost control
        vm.prank(alice);
        vm.expectRevert(DIDRegistry.NotIdentityOwner.selector);
        did.changeOwner(alice, alice);
    }

    function test_OnlyOwnerCanChange() public {
        vm.prank(newKey);
        vm.expectRevert(DIDRegistry.NotIdentityOwner.selector);
        did.changeOwner(alice, newKey);
    }

    function test_Delegates() public {
        vm.prank(alice);
        did.addDelegate(alice, SIG_AUTH, agent, 1 days);
        assertTrue(did.validDelegate(alice, SIG_AUTH, agent));

        vm.warp(block.timestamp + 1 days + 1);
        assertFalse(did.validDelegate(alice, SIG_AUTH, agent));
    }

    function test_RevokeDelegate() public {
        vm.startPrank(alice);
        did.addDelegate(alice, SIG_AUTH, agent, 1 days);
        did.revokeDelegate(alice, SIG_AUTH, agent);
        vm.stopPrank();
        assertFalse(did.validDelegate(alice, SIG_AUTH, agent));
    }

    function test_ChangeOwnerFromRequiresAgent() public {
        vm.expectRevert(DIDRegistry.NotRecoveryAgent.selector);
        did.changeOwnerFrom(alice, newKey);
    }

    // ---- RecoveryModule ----

    function _configureRecovery() internal {
        address[] memory guardians = new address[](3);
        guardians[0] = g1;
        guardians[1] = g2;
        guardians[2] = g3;
        vm.startPrank(alice);
        recovery.configure(alice, guardians, 2, 1 days);
        did.setRecoveryAgent(alice, address(recovery));
        vm.stopPrank();
    }

    function test_RecoveryHappyPath() public {
        _configureRecovery();

        vm.prank(g1);
        recovery.propose(alice, newKey);

        // not enough approvals yet
        vm.warp(block.timestamp + 1 days + 1);
        vm.expectRevert(RecoveryModule.NotReady.selector);
        recovery.execute(alice);

        vm.prank(g2);
        recovery.approve(alice);

        recovery.execute(alice);
        assertEq(did.identityOwner(alice), newKey);
    }

    function test_RecoveryTimelockEnforced() public {
        _configureRecovery();
        vm.prank(g1);
        recovery.propose(alice, newKey);
        vm.prank(g2);
        recovery.approve(alice);

        vm.expectRevert(RecoveryModule.NotReady.selector);
        recovery.execute(alice);
    }

    function test_OwnerCanCancelRecovery() public {
        _configureRecovery();
        vm.prank(g1);
        recovery.propose(alice, newKey);
        vm.prank(g2);
        recovery.approve(alice);

        vm.prank(alice);
        recovery.cancel(alice);

        vm.warp(block.timestamp + 2 days);
        vm.expectRevert(RecoveryModule.NoActiveAttempt.selector);
        recovery.execute(alice);
    }

    function test_NonGuardianCannotPropose() public {
        _configureRecovery();
        vm.prank(agent);
        vm.expectRevert(RecoveryModule.NotGuardian.selector);
        recovery.propose(alice, newKey);
    }

    function test_ProposeWhileActiveBlocked() public {
        _configureRecovery();
        vm.prank(g1);
        recovery.propose(alice, newKey);

        // a lone guardian can't reset the clock while an attempt is live
        vm.prank(g2);
        vm.expectRevert(RecoveryModule.AttemptActive.selector);
        recovery.propose(alice, agent);

        // once stale (timelock + TTL), a fresh proposal is allowed
        vm.warp(block.timestamp + 1 days + recovery.ATTEMPT_TTL() + 1);
        vm.prank(g2);
        recovery.propose(alice, agent);
    }

    function test_StaleAttemptCannotExecute() public {
        _configureRecovery();
        vm.prank(g1);
        recovery.propose(alice, newKey);
        vm.prank(g2);
        recovery.approve(alice);

        vm.warp(block.timestamp + 1 days + recovery.ATTEMPT_TTL() + 1);
        vm.expectRevert(RecoveryModule.AttemptExpired.selector);
        recovery.execute(alice);
    }

    function test_DoubleApproveBlocked() public {
        _configureRecovery();
        vm.prank(g1);
        recovery.propose(alice, newKey);
        vm.prank(g1);
        vm.expectRevert(RecoveryModule.AlreadyApproved.selector);
        recovery.approve(alice);
    }

    // ---- DelegationRegistry ----

    function test_GrantAndCheck() public {
        vm.prank(alice);
        delegation.grant(alice, agent, SCOPE, block.timestamp + 1 hours);
        assertTrue(delegation.isAuthorized(alice, agent, SCOPE));

        vm.warp(block.timestamp + 1 hours + 1);
        assertFalse(delegation.isAuthorized(alice, agent, SCOPE));
    }

    function test_Revoke() public {
        vm.startPrank(alice);
        delegation.grant(alice, agent, SCOPE, block.timestamp + 1 hours);
        delegation.revoke(alice, agent, SCOPE);
        vm.stopPrank();
        assertFalse(delegation.isAuthorized(alice, agent, SCOPE));
    }

    function test_RevokeAllKillsEverything() public {
        vm.startPrank(alice);
        delegation.grant(alice, agent, SCOPE, block.timestamp + 1 hours);
        delegation.grant(alice, newKey, SCOPE, block.timestamp + 1 hours);
        delegation.revokeAll(alice);
        vm.stopPrank();
        assertFalse(delegation.isAuthorized(alice, agent, SCOPE));
        assertFalse(delegation.isAuthorized(alice, newKey, SCOPE));
    }

    function test_ControlFollowsDIDOwner() public {
        vm.prank(alice);
        did.changeOwner(alice, newKey);

        // old key can no longer grant
        vm.prank(alice);
        vm.expectRevert(DIDControlled.NotIdentityOwner.selector);
        delegation.grant(alice, agent, SCOPE, block.timestamp + 1 hours);

        // new key can
        vm.prank(newKey);
        delegation.grant(alice, agent, SCOPE, block.timestamp + 1 hours);
        assertTrue(delegation.isAuthorized(alice, agent, SCOPE));
    }
}
