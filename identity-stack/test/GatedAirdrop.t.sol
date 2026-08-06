// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ZKFixtureBase} from "./ZKFixtureBase.sol";
import {SemaphoreVerifier} from "@semaphore-protocol/contracts/base/SemaphoreVerifier.sol";
import {ISemaphoreVerifier} from "@semaphore-protocol/contracts/interfaces/ISemaphoreVerifier.sol";
import {DIDRegistry} from "../src/DIDRegistry.sol";
import {SchemaRegistry} from "../src/SchemaRegistry.sol";
import {IssuerRegistry} from "../src/IssuerRegistry.sol";
import {TrustRegistry, ROLE_ISSUER} from "../src/TrustRegistry.sol";
import {CredentialTreeRegistry} from "../src/CredentialTreeRegistry.sol";
import {NullifierRegistry} from "../src/NullifierRegistry.sol";
import {ProofGateway} from "../src/ProofGateway.sol";
import {GatedAirdrop} from "../src/GatedAirdrop.sol";

/// The whole stack composed: schema -> issuer -> accreditation -> credential
/// tree -> ZK proof -> sybil-resistant claim. Requires fixtures.
contract GatedAirdropTest is ZKFixtureBase {
    DIDRegistry did;
    SchemaRegistry schemas;
    IssuerRegistry issuers;
    TrustRegistry trust;
    CredentialTreeRegistry trees;
    NullifierRegistry nullifiers;
    ProofGateway gateway;
    GatedAirdrop airdrop;

    address issuer = makeAddr("issuer");
    address authority = makeAddr("authority");
    bytes32 schemaId;
    uint256 treeId;

    function setUp() public {
        _loadFixtures();
        if (!hasFixtures) return;

        did = new DIDRegistry();
        schemas = new SchemaRegistry();
        issuers = new IssuerRegistry(did, schemas);
        trust = new TrustRegistry(did);
        trees = new CredentialTreeRegistry(did);
        nullifiers = new NullifierRegistry();
        gateway = new ProofGateway(
            ISemaphoreVerifier(address(new SemaphoreVerifier())), trees, nullifiers
        );

        schemaId = schemas.register("ipfs://personhood-schema", keccak256("personhood-v1"));

        vm.startPrank(issuer);
        issuers.register(issuer, "ipfs://issuer-meta");
        issuers.declareSchema(issuer, schemaId);
        treeId = trees.createTree(issuer, 1 hours);
        trees.issueMany(treeId, _commitments());
        vm.stopPrank();

        vm.prank(authority);
        trust.accredit(authority, issuer, ROLE_ISSUER, schemaId, 0, "ipfs://accreditation");

        airdrop = new GatedAirdrop(gateway, trust, authority, schemaId, treeId, CAMPAIGN_SCOPE);
    }

    function test_ClaimHappyPath() public {
        _requireFixtures();
        vm.prank(CLAIMANT_BEEF);
        airdrop.claim(_proof(".airdropBob"));
        assertEq(airdrop.claims(CLAIMANT_BEEF), 1);
    }

    function test_SameProofReplayBlocked() public {
        _requireFixtures();
        vm.startPrank(CLAIMANT_BEEF);
        airdrop.claim(_proof(".airdropBob"));
        vm.expectRevert(NullifierRegistry.NullifierAlreadyUsed.selector);
        airdrop.claim(_proof(".airdropBob"));
        vm.stopPrank();
    }

    /// One claim per PERSON, not per address: same credential holder, fresh
    /// proof, different wallet — still blocked by the nullifier.
    function test_SamePersonDifferentAddressBlocked() public {
        _requireFixtures();
        vm.prank(CLAIMANT_BEEF);
        airdrop.claim(_proof(".airdropBob"));

        vm.prank(CLAIMANT_CAFE);
        vm.expectRevert(NullifierRegistry.NullifierAlreadyUsed.selector);
        airdrop.claim(_proof(".airdropBobSecond"));
    }

    function test_DifferentPersonCanClaim() public {
        _requireFixtures();
        vm.prank(CLAIMANT_BEEF);
        airdrop.claim(_proof(".airdropBob"));

        vm.prank(CLAIMANT_CAFE);
        airdrop.claim(_proof(".airdropCarol"));
        assertEq(airdrop.claims(CLAIMANT_CAFE), 1);
    }

    function test_ProofBoundToCaller() public {
        _requireFixtures();
        // bob's proof commits to 0xBEEF; 0xCAFE cannot front-run it
        vm.prank(CLAIMANT_CAFE);
        vm.expectRevert(GatedAirdrop.ProofNotBoundToCaller.selector);
        airdrop.claim(_proof(".airdropBob"));
    }

    function test_WrongScopeBlocked() public {
        _requireFixtures();
        // gateway proof has scope 111, not the campaign scope
        vm.prank(CLAIMANT_BEEF);
        vm.expectRevert(GatedAirdrop.WrongScope.selector);
        airdrop.claim(_proof(".gatewayProof"));
    }

    /// Nullifier griefing: a mempool watcher front-runs a pending claim with a
    /// direct `gateway.validate` of the same proof. Namespacing consumption by
    /// caller means the griefer only burns the nullifier in their own scope, so
    /// the honest claim still lands.
    function test_DirectGatewayValidateCannotBurnClaim() public {
        _requireFixtures();
        ProofGateway.Proof memory stolen = _proof(".airdropBob");

        vm.prank(makeAddr("griefer"));
        gateway.validate(treeId, stolen);

        vm.prank(CLAIMANT_BEEF);
        airdrop.claim(stolen);
        assertEq(airdrop.claims(CLAIMANT_BEEF), 1);
    }

    function test_DeaccreditedIssuerBlocked() public {
        _requireFixtures();
        vm.prank(authority);
        trust.revoke(authority, issuer, ROLE_ISSUER, schemaId);

        vm.prank(CLAIMANT_BEEF);
        vm.expectRevert(GatedAirdrop.IssuerNotAccredited.selector);
        airdrop.claim(_proof(".airdropBob"));
    }
}
