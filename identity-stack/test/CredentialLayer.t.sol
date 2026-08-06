// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {DIDRegistry} from "../src/DIDRegistry.sol";
import {DIDControlled} from "../src/DIDControlled.sol";
import {SchemaRegistry} from "../src/SchemaRegistry.sol";
import {IssuerRegistry} from "../src/IssuerRegistry.sol";
import {TrustRegistry, ROLE_ISSUER, ROLE_ACCREDITOR} from "../src/TrustRegistry.sol";
import {AttestationRegistry} from "../src/AttestationRegistry.sol";

contract CredentialLayerTest is Test {
    DIDRegistry did;
    SchemaRegistry schemas;
    IssuerRegistry issuers;
    TrustRegistry trust;
    AttestationRegistry attestations;

    address issuer = makeAddr("issuer");
    address root = makeAddr("rootAuthority");
    address accreditor = makeAddr("accreditor");
    address subject = makeAddr("subject");
    address rando = makeAddr("rando");

    bytes32 schemaId;

    function setUp() public {
        did = new DIDRegistry();
        schemas = new SchemaRegistry();
        issuers = new IssuerRegistry(did, schemas);
        trust = new TrustRegistry(did);
        attestations = new AttestationRegistry(did, schemas);

        schemaId = schemas.register("ipfs://kyc-schema-v1", keccak256("kyc-schema-v1-content"));
    }

    // ---- SchemaRegistry ----

    function test_SchemaExists() public view {
        assertTrue(schemas.exists(schemaId));
        assertFalse(schemas.exists(bytes32(uint256(1))));
    }

    function test_DuplicateSchemaReverts() public {
        vm.expectRevert(SchemaRegistry.SchemaAlreadyRegistered.selector);
        schemas.register("ipfs://kyc-schema-v1", keccak256("kyc-schema-v1-content"));
    }

    // ---- IssuerRegistry ----

    function test_RegisterAndDeclare() public {
        vm.startPrank(issuer);
        issuers.register(issuer, "ipfs://issuer-meta");
        issuers.declareSchema(issuer, schemaId);
        vm.stopPrank();
        assertTrue(issuers.issuesSchema(issuer, schemaId));
    }

    function test_DeclareUnknownSchemaReverts() public {
        vm.startPrank(issuer);
        issuers.register(issuer, "ipfs://issuer-meta");
        vm.expectRevert(IssuerRegistry.UnknownSchema.selector);
        issuers.declareSchema(issuer, bytes32(uint256(99)));
        vm.stopPrank();
    }

    function test_InactiveIssuerDoesNotIssue() public {
        vm.startPrank(issuer);
        issuers.register(issuer, "ipfs://issuer-meta");
        issuers.declareSchema(issuer, schemaId);
        issuers.setActive(issuer, false);
        vm.stopPrank();
        assertFalse(issuers.issuesSchema(issuer, schemaId));
    }

    function test_IssuerControlFollowsDID() public {
        vm.prank(issuer);
        issuers.register(issuer, "ipfs://issuer-meta");

        address newKey = makeAddr("newKey");
        vm.prank(issuer);
        did.changeOwner(issuer, newKey);

        vm.prank(issuer);
        vm.expectRevert(DIDControlled.NotIdentityOwner.selector);
        issuers.setActive(issuer, false);

        vm.prank(newKey);
        issuers.setActive(issuer, false);
        assertFalse(issuers.issuesSchema(issuer, schemaId));
    }

    // ---- TrustRegistry ----

    function test_AccreditAndCheck() public {
        vm.prank(root);
        trust.accredit(root, issuer, ROLE_ISSUER, schemaId, 0, "ipfs://accreditation");
        assertTrue(trust.isAccredited(root, issuer, ROLE_ISSUER, schemaId));
        assertFalse(trust.isAccredited(root, rando, ROLE_ISSUER, schemaId));
    }

    function test_RevokedAccreditationFails() public {
        vm.startPrank(root);
        trust.accredit(root, issuer, ROLE_ISSUER, schemaId, 0, "");
        trust.revoke(root, issuer, ROLE_ISSUER, schemaId);
        vm.stopPrank();
        assertFalse(trust.isAccredited(root, issuer, ROLE_ISSUER, schemaId));
    }

    function test_ExpiredAccreditationFails() public {
        vm.prank(root);
        trust.accredit(root, issuer, ROLE_ISSUER, schemaId, uint64(block.timestamp + 1 days), "");
        assertTrue(trust.isAccredited(root, issuer, ROLE_ISSUER, schemaId));
        vm.warp(block.timestamp + 1 days + 1);
        assertFalse(trust.isAccredited(root, issuer, ROLE_ISSUER, schemaId));
    }

    function test_AccreditationChain() public {
        // root accredits accreditor as ROLE_ACCREDITOR; accreditor accredits issuer as ROLE_ISSUER
        vm.prank(root);
        trust.accredit(root, accreditor, ROLE_ACCREDITOR, schemaId, 0, "");
        vm.prank(accreditor);
        trust.accredit(accreditor, issuer, ROLE_ISSUER, schemaId, 0, "");

        address[] memory path = new address[](3);
        path[0] = root;
        path[1] = accreditor;
        path[2] = issuer;
        assertTrue(trust.checkChain(path, ROLE_ISSUER, schemaId));

        // broken chain: root never accredited rando
        path[1] = rando;
        assertFalse(trust.checkChain(path, ROLE_ISSUER, schemaId));
    }

    // ---- AttestationRegistry ----

    function test_AttestAndValidate() public {
        vm.prank(issuer);
        bytes32 uid = attestations.attest(issuer, subject, schemaId, 0, abi.encode(true));
        assertTrue(attestations.isValid(uid));
    }

    function test_RevokeAttestation() public {
        vm.startPrank(issuer);
        bytes32 uid = attestations.attest(issuer, subject, schemaId, 0, "");
        attestations.revoke(issuer, uid);
        vm.stopPrank();
        assertFalse(attestations.isValid(uid));
    }

    function test_ExpiryRespected() public {
        vm.prank(issuer);
        bytes32 uid = attestations.attest(issuer, subject, schemaId, uint64(block.timestamp + 1 hours), "");
        assertTrue(attestations.isValid(uid));
        vm.warp(block.timestamp + 1 hours + 1);
        assertFalse(attestations.isValid(uid));
    }

    function test_OnlyIssuerCanRevoke() public {
        vm.prank(issuer);
        bytes32 uid = attestations.attest(issuer, subject, schemaId, 0, "");
        vm.prank(rando);
        vm.expectRevert(DIDControlled.NotIdentityOwner.selector);
        attestations.revoke(issuer, uid);
        // and a different identity can't revoke someone else's attestation
        vm.prank(rando);
        vm.expectRevert(AttestationRegistry.NotAttestationIssuer.selector);
        attestations.revoke(rando, uid);
    }

    function test_AttestUnknownSchemaReverts() public {
        vm.prank(issuer);
        vm.expectRevert(AttestationRegistry.UnknownSchema.selector);
        attestations.attest(issuer, subject, bytes32(uint256(99)), 0, "");
    }
}
