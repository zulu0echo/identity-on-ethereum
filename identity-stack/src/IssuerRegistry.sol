// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {DIDRegistry} from "./DIDRegistry.sol";
import {DIDControlled} from "./DIDControlled.sol";
import {SchemaRegistry} from "./SchemaRegistry.sol";

/// @title IssuerRegistry — permissionless issuer self-registration + schema declarations.
/// @notice Registration asserts nothing about trustworthiness; it's a stable,
/// discoverable anchor (DID + metadata) that TrustRegistry accreditations and
/// verifier policies can point at. Declared schemas are the issuer's public
/// commitment to what it issues ("issuer schemas").
contract IssuerRegistry is DIDControlled {
    struct Issuer {
        string metadataURI;
        uint64 registeredAt;
        bool active;
    }

    SchemaRegistry public immutable schemaRegistry;

    mapping(address => Issuer) public issuers;
    /// issuer identity => schemaId => declared
    mapping(address => mapping(bytes32 => bool)) public declaredSchemas;

    event IssuerRegistered(address indexed identity, string metadataURI);
    event IssuerStatusChanged(address indexed identity, bool active);
    event SchemaDeclared(address indexed identity, bytes32 indexed schemaId);
    event SchemaWithdrawn(address indexed identity, bytes32 indexed schemaId);

    error NotRegistered();
    error AlreadyRegistered();
    error UnknownSchema();

    constructor(DIDRegistry _did, SchemaRegistry _schemas) DIDControlled(_did) {
        schemaRegistry = _schemas;
    }

    function register(address identity, string calldata metadataURI) external onlyIdentityOwner(identity) {
        if (issuers[identity].registeredAt != 0) revert AlreadyRegistered();
        issuers[identity] = Issuer(metadataURI, uint64(block.timestamp), true);
        emit IssuerRegistered(identity, metadataURI);
    }

    function setActive(address identity, bool active) external onlyIdentityOwner(identity) {
        if (issuers[identity].registeredAt == 0) revert NotRegistered();
        issuers[identity].active = active;
        emit IssuerStatusChanged(identity, active);
    }

    function declareSchema(address identity, bytes32 schemaId) external onlyIdentityOwner(identity) {
        if (issuers[identity].registeredAt == 0) revert NotRegistered();
        if (!schemaRegistry.exists(schemaId)) revert UnknownSchema();
        declaredSchemas[identity][schemaId] = true;
        emit SchemaDeclared(identity, schemaId);
    }

    function withdrawSchema(address identity, bytes32 schemaId) external onlyIdentityOwner(identity) {
        if (issuers[identity].registeredAt == 0) revert NotRegistered();
        declaredSchemas[identity][schemaId] = false;
        emit SchemaWithdrawn(identity, schemaId);
    }

    /// @notice True iff the issuer is registered, active, and declares this schema.
    function issuesSchema(address identity, bytes32 schemaId) external view returns (bool) {
        Issuer storage i = issuers[identity];
        return i.registeredAt != 0 && i.active && declaredSchemas[identity][schemaId];
    }
}
