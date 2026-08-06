// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {DIDRegistry} from "../src/DIDRegistry.sol";
import {DIDControlled} from "../src/DIDControlled.sol";
import {CredentialTreeRegistry} from "../src/CredentialTreeRegistry.sol";

/// Non-ZK behaviour of the LeanIMT credential trees (issue, revoke, root
/// history). Cross-checks against JS-computed roots live in ZKProof.t.sol.
contract CredentialTreeTest is Test {
    DIDRegistry did;
    CredentialTreeRegistry trees;

    address issuer = makeAddr("issuer");
    address rando = makeAddr("rando");
    uint256 treeId;

    function setUp() public {
        did = new DIDRegistry();
        trees = new CredentialTreeRegistry(did);
        vm.prank(issuer);
        treeId = trees.createTree(issuer, 1 hours);
    }

    function test_IssueAddsCredential() public {
        vm.prank(issuer);
        trees.issue(treeId, 12345);
        assertTrue(trees.hasCredential(treeId, 12345));
        assertEq(trees.treeSize(treeId), 1);
        // single-leaf LeanIMT: root == leaf
        assertEq(trees.currentRoot(treeId), 12345);
    }

    function test_OnlyIssuerIssues() public {
        vm.prank(rando);
        vm.expectRevert(CredentialTreeRegistry.NotTreeIssuer.selector);
        trees.issue(treeId, 12345);
    }

    function test_IssueMany() public {
        uint256[] memory commitments = new uint256[](3);
        commitments[0] = 111;
        commitments[1] = 222;
        commitments[2] = 333;
        vm.prank(issuer);
        trees.issueMany(treeId, commitments);
        assertEq(trees.treeSize(treeId), 3);
        assertEq(trees.treeDepth(treeId), 2);
        assertTrue(trees.hasCredential(treeId, 222));
    }

    function test_RevokeSingleLeaf() public {
        vm.startPrank(issuer);
        trees.issue(treeId, 12345);
        // single-leaf tree: no siblings needed
        uint256[] memory siblings = new uint256[](0);
        trees.revoke(treeId, 12345, siblings);
        vm.stopPrank();
        assertFalse(trees.hasCredential(treeId, 12345));
        assertEq(trees.currentRoot(treeId), 0);
    }

    function test_RevokeTwoLeafTree() public {
        vm.startPrank(issuer);
        trees.issue(treeId, 111);
        trees.issue(treeId, 222);
        uint256 rootBefore = trees.currentRoot(treeId);

        uint256[] memory siblings = new uint256[](1);
        siblings[0] = 111; // sibling of leaf 222 at level 0
        trees.revoke(treeId, 222, siblings);
        vm.stopPrank();

        assertFalse(trees.hasCredential(treeId, 222));
        assertTrue(trees.hasCredential(treeId, 111));
        assertTrue(trees.currentRoot(treeId) != rootBefore);
    }

    function test_RootHistoryWindow() public {
        vm.startPrank(issuer);
        trees.issue(treeId, 111);
        uint256 oldRoot = trees.currentRoot(treeId);
        trees.issue(treeId, 222);
        vm.stopPrank();

        // old root still valid inside the window
        assertTrue(trees.isValidRoot(treeId, oldRoot));
        assertTrue(trees.isValidRoot(treeId, trees.currentRoot(treeId)));

        vm.warp(block.timestamp + 1 hours + 1);
        assertFalse(trees.isValidRoot(treeId, oldRoot));
        // current root never expires
        assertTrue(trees.isValidRoot(treeId, trees.currentRoot(treeId)));
    }

    function test_UnknownRootInvalid() public view {
        assertFalse(trees.isValidRoot(treeId, 999999));
    }

    function test_IssuerControlFollowsDID() public {
        address newKey = makeAddr("newKey");
        vm.prank(issuer);
        did.changeOwner(issuer, newKey);

        vm.prank(issuer);
        vm.expectRevert(CredentialTreeRegistry.NotTreeIssuer.selector);
        trees.issue(treeId, 12345);

        vm.prank(newKey);
        trees.issue(treeId, 12345);
        assertTrue(trees.hasCredential(treeId, 12345));
    }
}
