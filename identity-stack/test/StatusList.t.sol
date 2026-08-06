// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {DIDRegistry} from "../src/DIDRegistry.sol";
import {DIDControlled} from "../src/DIDControlled.sol";
import {StatusListRegistry} from "../src/StatusListRegistry.sol";

contract StatusListTest is Test {
    DIDRegistry did;
    StatusListRegistry statusLists;

    address issuer = makeAddr("issuer");
    address rando = makeAddr("rando");

    uint256 constant REVOCATION_LIST = 0;
    uint256 constant SUSPENSION_LIST = 1;

    function setUp() public {
        did = new DIDRegistry();
        statusLists = new StatusListRegistry(did);
        vm.startPrank(issuer);
        statusLists.createList(issuer, REVOCATION_LIST, StatusListRegistry.Purpose.Revocation, "ipfs://list-meta");
        statusLists.createList(issuer, SUSPENSION_LIST, StatusListRegistry.Purpose.Suspension, "");
        vm.stopPrank();
    }

    function test_RevokeCredential() public {
        assertFalse(statusLists.getStatus(issuer, REVOCATION_LIST, 7));
        vm.prank(issuer);
        statusLists.setStatus(issuer, REVOCATION_LIST, 7, true);
        assertTrue(statusLists.getStatus(issuer, REVOCATION_LIST, 7));
    }

    function test_WordPacking() public {
        // indices 255 and 256 land in different words; both must work independently
        vm.startPrank(issuer);
        statusLists.setStatus(issuer, REVOCATION_LIST, 255, true);
        statusLists.setStatus(issuer, REVOCATION_LIST, 256, true);
        vm.stopPrank();
        assertTrue(statusLists.getStatus(issuer, REVOCATION_LIST, 255));
        assertTrue(statusLists.getStatus(issuer, REVOCATION_LIST, 256));
        assertFalse(statusLists.getStatus(issuer, REVOCATION_LIST, 254));
        assertFalse(statusLists.getStatus(issuer, REVOCATION_LIST, 257));
    }

    function test_RevocationIsPermanent() public {
        vm.startPrank(issuer);
        statusLists.setStatus(issuer, REVOCATION_LIST, 7, true);
        vm.expectRevert(StatusListRegistry.RevocationIsPermanent.selector);
        statusLists.setStatus(issuer, REVOCATION_LIST, 7, false);
        vm.stopPrank();
    }

    function test_SuspensionCanBeLifted() public {
        vm.startPrank(issuer);
        statusLists.setStatus(issuer, SUSPENSION_LIST, 3, true);
        assertTrue(statusLists.getStatus(issuer, SUSPENSION_LIST, 3));
        statusLists.setStatus(issuer, SUSPENSION_LIST, 3, false);
        vm.stopPrank();
        assertFalse(statusLists.getStatus(issuer, SUSPENSION_LIST, 3));
    }

    function test_OnlyIssuerWrites() public {
        vm.prank(rando);
        vm.expectRevert(DIDControlled.NotIdentityOwner.selector);
        statusLists.setStatus(issuer, REVOCATION_LIST, 7, true);
    }

    function test_DuplicateListReverts() public {
        vm.prank(issuer);
        vm.expectRevert(StatusListRegistry.ListExists.selector);
        statusLists.createList(issuer, REVOCATION_LIST, StatusListRegistry.Purpose.Suspension, "");
    }

    function test_UnknownListReverts() public {
        vm.prank(issuer);
        vm.expectRevert(StatusListRegistry.UnknownList.selector);
        statusLists.setStatus(issuer, 42, 0, true);
    }
}
