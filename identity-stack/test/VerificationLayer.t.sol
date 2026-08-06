// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {DIDRegistry} from "../src/DIDRegistry.sol";
import {DIDControlled} from "../src/DIDControlled.sol";
import {VerifierRegistry} from "../src/VerifierRegistry.sol";
import {PolicyRegistry} from "../src/PolicyRegistry.sol";
import {PaymentRails} from "../src/PaymentRails.sol";

contract VerificationLayerTest is Test {
    DIDRegistry did;
    VerifierRegistry verifiers;
    PolicyRegistry policies;
    PaymentRails rails;

    address verifier = makeAddr("verifier");
    address issuer = makeAddr("issuer");
    address rando = makeAddr("rando");

    function setUp() public {
        did = new DIDRegistry();
        verifiers = new VerifierRegistry(did);
        policies = new PolicyRegistry(did);
        rails = new PaymentRails(did);
    }

    // ---- VerifierRegistry ----

    function test_RegisterVerifier() public {
        vm.prank(verifier);
        verifiers.register(verifier, "ipfs://verifier-meta");
        assertTrue(verifiers.isActive(verifier));
    }

    function test_DeactivateVerifier() public {
        vm.startPrank(verifier);
        verifiers.register(verifier, "");
        verifiers.setActive(verifier, false);
        vm.stopPrank();
        assertFalse(verifiers.isActive(verifier));
    }

    // ---- PolicyRegistry ----

    function test_PublishActivatesPolicy() public {
        vm.prank(verifier);
        uint256 id = policies.publish(verifier, "ipfs://policy-v1", keccak256("v1"));
        (uint256 activeId, PolicyRegistry.Policy memory p) = policies.activePolicy(verifier);
        assertEq(activeId, id);
        assertEq(p.contentHash, keccak256("v1"));
    }

    function test_VersioningAndRollback() public {
        vm.startPrank(verifier);
        policies.publish(verifier, "ipfs://policy-v1", keccak256("v1"));
        policies.publish(verifier, "ipfs://policy-v2", keccak256("v2"));
        (uint256 activeId,) = policies.activePolicy(verifier);
        assertEq(activeId, 1);

        policies.setActive(verifier, 0);
        vm.stopPrank();
        (activeId,) = policies.activePolicy(verifier);
        assertEq(activeId, 0);
        assertEq(policies.policyCount(verifier), 2);
    }

    function test_NoPolicyReverts() public {
        vm.expectRevert(PolicyRegistry.NoSuchPolicy.selector);
        policies.activePolicy(verifier);
    }

    function test_OnlyVerifierOwnerPublishes() public {
        vm.prank(rando);
        vm.expectRevert(DIDControlled.NotIdentityOwner.selector);
        policies.publish(verifier, "", 0);
    }

    // ---- PaymentRails ----

    function test_SettlementFlow() public {
        vm.prank(issuer);
        rails.setFee(issuer, 0.01 ether);

        hoax(verifier, 1 ether);
        rails.deposit{value: 0.05 ether}(verifier);

        vm.prank(verifier);
        rails.settle(verifier, issuer, keccak256("session-1"), 0.01 ether);

        assertEq(rails.balanceOf(verifier), 0.04 ether);
        assertEq(rails.balanceOf(issuer), 0.01 ether);
    }

    function test_InsufficientBalanceReverts() public {
        vm.prank(issuer);
        rails.setFee(issuer, 0.01 ether);
        vm.prank(verifier);
        vm.expectRevert(PaymentRails.InsufficientBalance.selector);
        rails.settle(verifier, issuer, keccak256("session-1"), 0.01 ether);
    }

    /// Receipts must name issuers who actually posted a price, or the event log
    /// is not an audit trail.
    function test_SettleAgainstUnpricedIssuerReverts() public {
        hoax(verifier, 1 ether);
        rails.deposit{value: 0.05 ether}(verifier);

        vm.prank(verifier);
        vm.expectRevert(PaymentRails.NoFeeSet.selector);
        rails.settle(verifier, makeAddr("neverSetAFee"), keccak256("session-1"), 1 ether);
    }

    function test_FeeHikeFrontRunBlocked() public {
        hoax(verifier, 1 ether);
        rails.deposit{value: 0.5 ether}(verifier);

        // issuer hikes the fee after the verifier decided to settle at 0.01
        vm.prank(issuer);
        rails.setFee(issuer, 0.5 ether);

        vm.prank(verifier);
        vm.expectRevert(PaymentRails.FeeTooHigh.selector);
        rails.settle(verifier, issuer, bytes32(0), 0.01 ether);
    }

    function test_IssuerWithdrawsEarnings() public {
        vm.prank(issuer);
        rails.setFee(issuer, 0.01 ether);
        hoax(verifier, 1 ether);
        rails.deposit{value: 0.01 ether}(verifier);
        vm.prank(verifier);
        rails.settle(verifier, issuer, bytes32(0), 0.01 ether);

        vm.prank(issuer);
        rails.withdraw(issuer, 0.01 ether);
        assertEq(issuer.balance, 0.01 ether);
        assertEq(rails.balanceOf(issuer), 0);
    }

    function test_RotatedIssuerKeepsEarnings() public {
        vm.prank(issuer);
        rails.setFee(issuer, 0.01 ether);
        hoax(verifier, 1 ether);
        rails.deposit{value: 0.01 ether}(verifier);
        vm.prank(verifier);
        rails.settle(verifier, issuer, bytes32(0), 0.01 ether);

        // issuer rotates its key; earnings follow the DID, not the old key
        address newKey = makeAddr("newIssuerKey");
        vm.prank(issuer);
        did.changeOwner(issuer, newKey);

        vm.prank(issuer);
        vm.expectRevert(DIDControlled.NotIdentityOwner.selector);
        rails.withdraw(issuer, 0.01 ether);

        vm.prank(newKey);
        rails.withdraw(issuer, 0.01 ether);
        assertEq(newKey.balance, 0.01 ether);
    }

    function test_OverWithdrawReverts() public {
        vm.prank(verifier);
        vm.expectRevert(PaymentRails.InsufficientBalance.selector);
        rails.withdraw(verifier, 1);
    }
}
