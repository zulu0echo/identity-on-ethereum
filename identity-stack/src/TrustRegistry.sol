// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {DIDRegistry} from "./DIDRegistry.sol";
import {DIDControlled} from "./DIDControlled.sol";

// Role constants shared across the stack. (Plain comment, not a NatSpec tag:
// solc rejects @notice on file-level constants.)
bytes32 constant ROLE_ISSUER = keccak256("ROLE_ISSUER");
bytes32 constant ROLE_VERIFIER = keccak256("ROLE_VERIFIER");
bytes32 constant ROLE_ACCREDITOR = keccak256("ROLE_ACCREDITOR");

/// @title TrustRegistry — who vouches for whom, for what role, for which schema.
/// @notice The layer above issuer/verifier registries. There is no global root:
/// any identity can accredit any other, and each relying party chooses which
/// authorities it treats as roots (eIDAS-style trusted lists, but plural).
/// `checkChain` walks root -> accreditor(s) -> subject.
contract TrustRegistry is DIDControlled {
    struct Accreditation {
        uint64 issuedAt;
        uint64 expiry; // 0 = no expiry
        uint64 revokedAt;
        string uri; // offchain accreditation document (terms, audit report, ...)
    }

    /// authority => subject => role => schemaId => accreditation
    mapping(address => mapping(address => mapping(bytes32 => mapping(bytes32 => Accreditation)))) public
        accreditations;

    event Accredited(
        address indexed authority, address indexed subject, bytes32 indexed role, bytes32 schemaId, uint64 expiry, string uri
    );
    event AccreditationRevoked(address indexed authority, address indexed subject, bytes32 indexed role, bytes32 schemaId);

    error NotAccredited();

    constructor(DIDRegistry _did) DIDControlled(_did) {}

    function accredit(
        address authority,
        address subject,
        bytes32 role,
        bytes32 schemaId,
        uint64 expiry,
        string calldata uri
    ) external onlyIdentityOwner(authority) {
        accreditations[authority][subject][role][schemaId] =
            Accreditation(uint64(block.timestamp), expiry, 0, uri);
        emit Accredited(authority, subject, role, schemaId, expiry, uri);
    }

    function revoke(address authority, address subject, bytes32 role, bytes32 schemaId)
        external
        onlyIdentityOwner(authority)
    {
        Accreditation storage a = accreditations[authority][subject][role][schemaId];
        if (a.issuedAt == 0) revert NotAccredited();
        a.revokedAt = uint64(block.timestamp);
        emit AccreditationRevoked(authority, subject, role, schemaId);
    }

    function isAccredited(address authority, address subject, bytes32 role, bytes32 schemaId)
        public
        view
        returns (bool)
    {
        Accreditation storage a = accreditations[authority][subject][role][schemaId];
        return a.issuedAt != 0 && a.revokedAt == 0 && (a.expiry == 0 || a.expiry >= block.timestamp);
    }

    /// @notice Verify an accreditation chain: path[0] is the relying party's
    /// chosen root; intermediate links must hold ROLE_ACCREDITOR, the final
    /// link grants `role` for `schemaId`.
    function checkChain(address[] calldata path, bytes32 role, bytes32 schemaId) external view returns (bool) {
        if (path.length < 2) return false;
        for (uint256 i = 0; i + 1 < path.length; i++) {
            bool last = i + 2 == path.length;
            if (!isAccredited(path[i], path[i + 1], last ? role : ROLE_ACCREDITOR, schemaId)) return false;
        }
        return true;
    }
}
