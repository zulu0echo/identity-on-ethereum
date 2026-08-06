// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {DIDRegistry} from "./DIDRegistry.sol";
import {DIDControlled} from "./DIDControlled.sol";

/// @title VerifierRegistry — "verified verifiers": a discoverable anchor for
/// relying parties, symmetrical to IssuerRegistry.
/// @notice Wallets consult this (plus TrustRegistry accreditations and the
/// verifier's published policy) before releasing a presentation — flipping the
/// usual asymmetry where only holders get vetted.
contract VerifierRegistry is DIDControlled {
    struct Verifier {
        string metadataURI;
        uint64 registeredAt;
        bool active;
    }

    mapping(address => Verifier) public verifiers;

    event VerifierRegistered(address indexed identity, string metadataURI);
    event VerifierStatusChanged(address indexed identity, bool active);

    error AlreadyRegistered();
    error NotRegistered();

    constructor(DIDRegistry _did) DIDControlled(_did) {}

    function register(address identity, string calldata metadataURI) external onlyIdentityOwner(identity) {
        if (verifiers[identity].registeredAt != 0) revert AlreadyRegistered();
        verifiers[identity] = Verifier(metadataURI, uint64(block.timestamp), true);
        emit VerifierRegistered(identity, metadataURI);
    }

    function setActive(address identity, bool active) external onlyIdentityOwner(identity) {
        if (verifiers[identity].registeredAt == 0) revert NotRegistered();
        verifiers[identity].active = active;
        emit VerifierStatusChanged(identity, active);
    }

    /// @notice True iff the verifier is registered and not paused. Both conjuncts
    /// are checked explicitly: `active` alone conflates "never registered" with
    /// "registered then paused", and callers gate presentations on this.
    function isActive(address identity) external view returns (bool) {
        Verifier storage v = verifiers[identity];
        return v.registeredAt != 0 && v.active;
    }
}
