// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {DIDRegistry} from "./DIDRegistry.sol";
import {DIDControlled} from "./DIDControlled.sol";
import {InternalLeanIMT, LeanIMTData} from "@zk-kit/lean-imt.sol/InternalLeanIMT.sol";

/// @title CredentialTreeRegistry — the ZK path for issuance + revocation.
/// @notice Each issuer owns Lean incremental Merkle trees of *credential
/// commitments* (Semaphore identity commitments — the holder's secret never
/// leaves their device). Issue = insert leaf; revoke = zero the leaf. Holders
/// prove membership (i.e. "I hold a currently-valid credential") in ZK against
/// the root. Old roots stay provable for `rootDuration` so an honest holder's
/// proof isn't invalidated mid-flight by an unrelated issuance.
contract CredentialTreeRegistry is DIDControlled {
    using InternalLeanIMT for LeanIMTData;

    struct TreeMeta {
        address issuer;
        uint256 rootDuration; // seconds an old root remains acceptable
    }

    mapping(uint256 => LeanIMTData) internal _trees;
    mapping(uint256 => TreeMeta) public meta;
    /// treeId => root => first-seen timestamp
    mapping(uint256 => mapping(uint256 => uint256)) public rootSeenAt;
    uint256 public treeCounter;

    event TreeCreated(uint256 indexed treeId, address indexed issuer, uint256 rootDuration);
    event CredentialIssued(uint256 indexed treeId, uint256 commitment, uint256 newRoot);
    event CredentialsIssued(uint256 indexed treeId, uint256[] commitments, uint256 newRoot);
    event CredentialRevoked(uint256 indexed treeId, uint256 commitment, uint256 newRoot);

    error NotTreeIssuer();

    constructor(DIDRegistry _did) DIDControlled(_did) {}

    modifier onlyTreeIssuer(uint256 treeId) {
        if (did.identityOwner(meta[treeId].issuer) != msg.sender) revert NotTreeIssuer();
        _;
    }

    function createTree(address issuer, uint256 rootDuration)
        external
        onlyIdentityOwner(issuer)
        returns (uint256 treeId)
    {
        treeId = treeCounter++;
        meta[treeId] = TreeMeta(issuer, rootDuration);
        emit TreeCreated(treeId, issuer, rootDuration);
    }

    function issue(uint256 treeId, uint256 commitment) external onlyTreeIssuer(treeId) {
        uint256 newRoot = _trees[treeId]._insert(commitment);
        rootSeenAt[treeId][newRoot] = block.timestamp;
        emit CredentialIssued(treeId, commitment, newRoot);
    }

    function issueMany(uint256 treeId, uint256[] calldata commitments) external onlyTreeIssuer(treeId) {
        uint256 newRoot = _trees[treeId]._insertMany(commitments);
        rootSeenAt[treeId][newRoot] = block.timestamp;
        emit CredentialsIssued(treeId, commitments, newRoot);
    }

    /// @param siblings Merkle siblings for the leaf, from the offchain tree copy.
    function revoke(uint256 treeId, uint256 commitment, uint256[] calldata siblings)
        external
        onlyTreeIssuer(treeId)
    {
        uint256 newRoot = _trees[treeId]._remove(commitment, siblings);
        rootSeenAt[treeId][newRoot] = block.timestamp;
        emit CredentialRevoked(treeId, commitment, newRoot);
    }

    function currentRoot(uint256 treeId) public view returns (uint256) {
        return _trees[treeId]._root();
    }

    /// @notice Current root, or any historical root still inside its validity window.
    function isValidRoot(uint256 treeId, uint256 root) external view returns (bool) {
        // empty/never-created trees have root 0 — never accept it
        if (_trees[treeId].size == 0) return false;
        if (root == currentRoot(treeId)) return true;
        uint256 seenAt = rootSeenAt[treeId][root];
        return seenAt != 0 && block.timestamp <= seenAt + meta[treeId].rootDuration;
    }

    function hasCredential(uint256 treeId, uint256 commitment) external view returns (bool) {
        return _trees[treeId]._has(commitment);
    }

    function treeSize(uint256 treeId) external view returns (uint256) {
        return _trees[treeId].size;
    }

    function treeDepth(uint256 treeId) external view returns (uint256) {
        return _trees[treeId].depth;
    }
}
