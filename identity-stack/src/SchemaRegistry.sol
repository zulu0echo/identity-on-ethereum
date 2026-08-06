// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title SchemaRegistry — permissionless, immutable credential schema registry.
/// @notice A schema is a content-addressed pointer: the URI hosts the full
/// definition (JSON Schema / W3C VC data model), the contentHash pins it.
/// Immutability is the point — issuers and verifiers can reference a schemaId
/// forever without trusting the host not to change the file.
contract SchemaRegistry {
    struct Schema {
        address creator;
        string uri;
        bytes32 contentHash;
        uint64 registeredAt;
    }

    mapping(bytes32 => Schema) public schemas;

    event SchemaRegistered(bytes32 indexed schemaId, address indexed creator, string uri, bytes32 contentHash);

    error SchemaAlreadyRegistered();

    function register(string calldata uri, bytes32 contentHash) external returns (bytes32 schemaId) {
        schemaId = keccak256(abi.encode(uri, contentHash));
        if (schemas[schemaId].registeredAt != 0) revert SchemaAlreadyRegistered();
        schemas[schemaId] = Schema(msg.sender, uri, contentHash, uint64(block.timestamp));
        emit SchemaRegistered(schemaId, msg.sender, uri, contentHash);
    }

    function exists(bytes32 schemaId) external view returns (bool) {
        return schemas[schemaId].registeredAt != 0;
    }
}
