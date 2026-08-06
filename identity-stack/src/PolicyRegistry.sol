// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {DIDRegistry} from "./DIDRegistry.sol";
import {DIDControlled} from "./DIDControlled.sol";

/// @title PolicyRegistry — verifiers publish what they ask for, immutably versioned.
/// @notice A policy document (accepted schemas, trusted roots, data-retention
/// promise) lives offchain; its hash lives here. Wallets can enforce "only
/// present to verifiers whose active policy I accept", and any policy change
/// is a permanent, timestamped public record — accountability by transparency.
contract PolicyRegistry is DIDControlled {
    struct Policy {
        string uri;
        bytes32 contentHash;
        uint64 publishedAt;
    }

    /// verifier => append-only policy versions
    mapping(address => Policy[]) internal _policies;
    /// verifier => active policy index + 1 (0 = none)
    mapping(address => uint256) internal _active;

    event PolicyPublished(address indexed verifier, uint256 indexed policyId, string uri, bytes32 contentHash);
    event ActivePolicyChanged(address indexed verifier, uint256 indexed policyId);

    error NoSuchPolicy();

    constructor(DIDRegistry _did) DIDControlled(_did) {}

    /// @notice Publishes a new version and makes it active.
    function publish(address verifier, string calldata uri, bytes32 contentHash)
        external
        onlyIdentityOwner(verifier)
        returns (uint256 policyId)
    {
        _policies[verifier].push(Policy(uri, contentHash, uint64(block.timestamp)));
        policyId = _policies[verifier].length - 1;
        _active[verifier] = policyId + 1;
        emit PolicyPublished(verifier, policyId, uri, contentHash);
        emit ActivePolicyChanged(verifier, policyId);
    }

    /// @notice Roll back / forward to a previously published version.
    function setActive(address verifier, uint256 policyId) external onlyIdentityOwner(verifier) {
        if (policyId >= _policies[verifier].length) revert NoSuchPolicy();
        _active[verifier] = policyId + 1;
        emit ActivePolicyChanged(verifier, policyId);
    }

    function activePolicy(address verifier) external view returns (uint256 policyId, Policy memory policy) {
        uint256 a = _active[verifier];
        if (a == 0) revert NoSuchPolicy();
        return (a - 1, _policies[verifier][a - 1]);
    }

    function policyCount(address verifier) external view returns (uint256) {
        return _policies[verifier].length;
    }

    function policyAt(address verifier, uint256 policyId) external view returns (Policy memory) {
        if (policyId >= _policies[verifier].length) revert NoSuchPolicy();
        return _policies[verifier][policyId];
    }
}
