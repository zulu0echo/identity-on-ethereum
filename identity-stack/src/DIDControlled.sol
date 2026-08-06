// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {DIDRegistry} from "./DIDRegistry.sol";

/// @title DIDControlled — shared base for registries whose entries are controlled
/// by a DID rather than a raw key. Rotating the key in DIDRegistry rotates
/// control of every registration everywhere, with no per-registry migration.
abstract contract DIDControlled {
    DIDRegistry public immutable did;

    error NotIdentityOwner();

    constructor(DIDRegistry _did) {
        did = _did;
    }

    modifier onlyIdentityOwner(address identity) {
        if (did.identityOwner(identity) != msg.sender) revert NotIdentityOwner();
        _;
    }
}
