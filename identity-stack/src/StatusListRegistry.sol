// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {DIDRegistry} from "./DIDRegistry.sol";
import {DIDControlled} from "./DIDControlled.sol";

/// @title StatusListRegistry — onchain W3C Bitstring Status List.
/// @notice One bit per credential, 256 credentials per storage word. The
/// credential (offchain VC) carries its (issuer, listId, index); any verifier
/// or contract checks validity with a single SLOAD. Revocation lists are
/// one-way (bits can only be set); suspension lists can be cleared (reinstated).
contract StatusListRegistry is DIDControlled {
    enum Purpose {
        None,
        Revocation,
        Suspension
    }

    struct List {
        Purpose purpose;
        string uri; // offchain description of what this list covers
    }

    /// issuer => listId => list metadata
    mapping(address => mapping(uint256 => List)) public lists;
    /// issuer => listId => wordIndex => 256 status bits
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) public words;

    event ListCreated(address indexed issuer, uint256 indexed listId, Purpose purpose, string uri);
    event StatusChanged(address indexed issuer, uint256 indexed listId, uint256 index, bool status);

    error ListExists();
    error UnknownList();
    error BadPurpose();
    error RevocationIsPermanent();

    constructor(DIDRegistry _did) DIDControlled(_did) {}

    function createList(address issuer, uint256 listId, Purpose purpose, string calldata uri)
        external
        onlyIdentityOwner(issuer)
    {
        if (purpose == Purpose.None) revert BadPurpose();
        if (lists[issuer][listId].purpose != Purpose.None) revert ListExists();
        lists[issuer][listId] = List(purpose, uri);
        emit ListCreated(issuer, listId, purpose, uri);
    }

    function setStatus(address issuer, uint256 listId, uint256 index, bool status)
        external
        onlyIdentityOwner(issuer)
    {
        List storage list = lists[issuer][listId];
        if (list.purpose == Purpose.None) revert UnknownList();
        if (!status && list.purpose == Purpose.Revocation) revert RevocationIsPermanent();

        uint256 word = words[issuer][listId][index >> 8];
        uint256 bit = 1 << (index & 0xff);
        words[issuer][listId][index >> 8] = status ? word | bit : word & ~bit;
        emit StatusChanged(issuer, listId, index, status);
    }

    /// @notice One SLOAD credential status check, callable by anything.
    function getStatus(address issuer, uint256 listId, uint256 index) external view returns (bool) {
        return words[issuer][listId][index >> 8] & (1 << (index & 0xff)) != 0;
    }
}
