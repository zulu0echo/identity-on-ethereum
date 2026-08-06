// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {DIDRegistry} from "./DIDRegistry.sol";
import {DIDControlled} from "./DIDControlled.sol";
import {SchemaRegistry} from "./SchemaRegistry.sol";

/// @title AttestationRegistry — direct onchain claims, for data that is not PII.
/// @notice The transparent path ("direct onchain proofs"): when the claim is
/// public by nature (contract audit passed, org membership, license grant),
/// putting it onchain in the clear gives every contract and indexer a single
/// source of truth with no proof machinery at all. EAS-shaped, minimal.
contract AttestationRegistry is DIDControlled {
    struct Attestation {
        address issuer;
        address subject;
        bytes32 schemaId;
        uint64 issuedAt;
        uint64 expiry; // 0 = no expiry
        uint64 revokedAt;
        bytes data; // schema-encoded claim body — must not contain PII
    }

    SchemaRegistry public immutable schemaRegistry;

    mapping(bytes32 => Attestation) public attestations;
    uint256 internal _nonce;

    event Attested(
        bytes32 indexed uid, address indexed issuer, address indexed subject, bytes32 schemaId, uint64 expiry
    );
    event AttestationRevoked(bytes32 indexed uid, address indexed issuer);

    error UnknownSchema();
    error UnknownAttestation();
    error NotAttestationIssuer();

    constructor(DIDRegistry _did, SchemaRegistry _schemas) DIDControlled(_did) {
        schemaRegistry = _schemas;
    }

    function attest(address issuer, address subject, bytes32 schemaId, uint64 expiry, bytes calldata data)
        external
        onlyIdentityOwner(issuer)
        returns (bytes32 uid)
    {
        if (!schemaRegistry.exists(schemaId)) revert UnknownSchema();
        uid = keccak256(abi.encode(issuer, subject, schemaId, data, block.timestamp, _nonce++));
        attestations[uid] = Attestation(issuer, subject, schemaId, uint64(block.timestamp), expiry, 0, data);
        emit Attested(uid, issuer, subject, schemaId, expiry);
    }

    function revoke(address issuer, bytes32 uid) external onlyIdentityOwner(issuer) {
        Attestation storage a = attestations[uid];
        if (a.issuedAt == 0) revert UnknownAttestation();
        if (a.issuer != issuer) revert NotAttestationIssuer();
        a.revokedAt = uint64(block.timestamp);
        emit AttestationRevoked(uid, issuer);
    }

    function isValid(bytes32 uid) external view returns (bool) {
        Attestation storage a = attestations[uid];
        return a.issuedAt != 0 && a.revokedAt == 0 && (a.expiry == 0 || a.expiry >= block.timestamp);
    }
}
