// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ZKFixtureBase} from "./ZKFixtureBase.sol";
import {SemaphoreVerifier} from "@semaphore-protocol/contracts/base/SemaphoreVerifier.sol";
import {ISemaphoreVerifier} from "@semaphore-protocol/contracts/interfaces/ISemaphoreVerifier.sol";
import {DIDRegistry} from "../src/DIDRegistry.sol";
import {CredentialTreeRegistry} from "../src/CredentialTreeRegistry.sol";
import {NullifierRegistry} from "../src/NullifierRegistry.sol";
import {ProofGateway} from "../src/ProofGateway.sol";

/// End-to-end ZK path with REAL Groth16 proofs: issue -> prove -> verify ->
/// revoke -> stale-root expiry. Requires fixtures (npm run fixtures).
contract ZKProofTest is ZKFixtureBase {
    DIDRegistry did;
    CredentialTreeRegistry trees;
    NullifierRegistry nullifiers;
    ProofGateway gateway;

    address issuer = makeAddr("issuer");
    uint256 treeId;

    function setUp() public {
        _loadFixtures();
        if (!hasFixtures) return;

        did = new DIDRegistry();
        trees = new CredentialTreeRegistry(did);
        nullifiers = new NullifierRegistry();
        gateway = new ProofGateway(
            ISemaphoreVerifier(address(new SemaphoreVerifier())), trees, nullifiers
        );

        vm.startPrank(issuer);
        treeId = trees.createTree(issuer, 1 hours);
        uint256[] memory commitments = _commitments();
        for (uint256 i = 0; i < commitments.length; i++) {
            trees.issue(treeId, commitments[i]);
        }
        vm.stopPrank();
    }

    /// The onchain LeanIMT (Poseidon in Solidity) must agree with the JS tree.
    function test_OnchainRootMatchesJS() public {
        _requireFixtures();
        assertEq(trees.currentRoot(treeId), _uint(".root0"));
    }

    function test_ValidProofVerifies() public {
        _requireFixtures();
        assertTrue(gateway.verify(treeId, _proof(".gatewayProof")));
    }

    function test_TamperedProofFails() public {
        _requireFixtures();
        ProofGateway.Proof memory p = _proof(".gatewayProof");
        p.nullifier += 1; // any public-signal change must break the pairing
        assertFalse(gateway.verify(treeId, p));
    }

    function test_ValidateConsumesNullifier() public {
        _requireFixtures();
        ProofGateway.Proof memory p = _proof(".gatewayProof");
        gateway.validate(treeId, p);
        vm.expectRevert(NullifierRegistry.NullifierAlreadyUsed.selector);
        gateway.validate(treeId, p);
    }

    function test_RevokeMatchesJSAndOldRootExpires() public {
        _requireFixtures();
        uint256[] memory commitments = _commitments();
        uint256[] memory siblings = _uints(".removeSiblings");

        vm.prank(issuer);
        trees.revoke(treeId, commitments[1], siblings);

        // onchain removal agrees with JS removal
        assertEq(trees.currentRoot(treeId), _uint(".root1"));
        assertFalse(trees.hasCredential(treeId, commitments[1]));

        // proof against the pre-revocation root still verifies inside the window...
        assertTrue(gateway.verify(treeId, _proof(".gatewayProof")));

        // ...and is rejected once the window closes
        vm.warp(block.timestamp + 1 hours + 1);
        vm.expectRevert(ProofGateway.UnknownOrExpiredRoot.selector);
        gateway.verify(treeId, _proof(".gatewayProof"));
    }

    function test_PostRevocationProofVerifies() public {
        _requireFixtures();
        uint256[] memory commitments = _commitments();
        vm.prank(issuer);
        trees.revoke(treeId, commitments[1], _uints(".removeSiblings"));

        // remaining holder proves against the NEW root
        assertTrue(gateway.verify(treeId, _proof(".postRevokeProof")));
    }
}
