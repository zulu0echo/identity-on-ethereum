// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ISemaphoreVerifier} from "@semaphore-protocol/contracts/interfaces/ISemaphoreVerifier.sol";
import {CredentialTreeRegistry} from "./CredentialTreeRegistry.sol";
import {NullifierRegistry} from "./NullifierRegistry.sol";

/// @title ProofGateway — verifies "I hold a valid, unrevoked credential from
/// issuer X" without learning which credential.
/// @notice Wraps the Semaphore v4 Groth16 verifier: checks the proof's Merkle
/// root against the issuer's credential tree, verifies the pairing, and (in
/// `validate`) consumes the nullifier so the same credential can't act twice
/// in the same scope. `message` binds arbitrary data (e.g. the recipient
/// address) into the proof to stop front-running.
contract ProofGateway {
    struct Proof {
        uint256 merkleTreeDepth;
        uint256 merkleTreeRoot;
        uint256 nullifier;
        uint256 message;
        uint256 scope;
        uint256[8] points;
    }

    ISemaphoreVerifier public immutable verifier;
    CredentialTreeRegistry public immutable trees;
    NullifierRegistry public immutable nullifiers;

    event ProofValidated(
        uint256 indexed treeId, address indexed consumer, uint256 indexed scope, uint256 nullifier, uint256 message
    );

    error InvalidProof();
    error UnknownOrExpiredRoot();
    error UnsupportedTreeDepth();

    constructor(ISemaphoreVerifier _verifier, CredentialTreeRegistry _trees, NullifierRegistry _nullifiers) {
        verifier = _verifier;
        trees = _trees;
        nullifiers = _nullifiers;
    }

    /// @notice Stateless check — free to call, consumes nothing.
    function verify(uint256 treeId, Proof calldata proof) public view returns (bool) {
        if (proof.merkleTreeDepth < 1 || proof.merkleTreeDepth > 32) revert UnsupportedTreeDepth();
        if (!trees.isValidRoot(treeId, proof.merkleTreeRoot)) revert UnknownOrExpiredRoot();

        return verifier.verifyProof(
            [proof.points[0], proof.points[1]],
            [[proof.points[2], proof.points[3]], [proof.points[4], proof.points[5]]],
            [proof.points[6], proof.points[7]],
            [proof.merkleTreeRoot, proof.nullifier, _hash(proof.message), _hash(proof.scope)],
            proof.merkleTreeDepth
        );
    }

    /// @notice Stateful check — additionally consumes the nullifier for
    /// (this gateway, the calling consumer, scope).
    function validate(uint256 treeId, Proof calldata proof) external {
        if (!verify(treeId, proof)) revert InvalidProof();
        nullifiers.consume(consumerScope(msg.sender, proof.scope), proof.nullifier);
        emit ProofValidated(treeId, msg.sender, proof.scope, proof.nullifier, proof.message);
    }

    /// @notice The nullifier namespace `validate` writes under for a given caller.
    /// @dev Nullifiers are namespaced per *calling contract*, not per gateway.
    /// Without this, anyone could copy a pending consumer call out of the
    /// mempool, front-run it with a direct `validate`, and burn the nullifier:
    /// the honest holder's call then reverts, and because nullifiers are
    /// deterministic per (secret, scope) they are locked out of that scope
    /// permanently. Binding the namespace to msg.sender makes a lifted proof
    /// useless anywhere except the consumer it was already headed for.
    /// Applications wanting one shared "one action per person" namespace should
    /// route through a common consumer contract rather than reusing a scope.
    function consumerScope(address consumer, uint256 scope) public pure returns (uint256) {
        return uint256(keccak256(abi.encode(consumer, scope)));
    }

    /// @dev Semaphore convention: keccak256 shifted into the snark scalar field.
    function _hash(uint256 value) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(value))) >> 8;
    }
}
