// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {DIDRegistry} from "./DIDRegistry.sol";
import {DIDControlled} from "./DIDControlled.sol";

/// @title DelegationRegistry — capability-scoped, expiring, revocable grants.
/// @notice "My agent may do X on my behalf until Y." Distinct from ERC-1056
/// key delegates: scopes are capabilities (e.g. keccak("present:kyc-credential")),
/// not key types. `revokeAll` bumps a nonce, killing every outstanding grant at once.
contract DelegationRegistry is DIDControlled {
    /// identity => nonce => agent => scope => valid-until timestamp
    mapping(address => mapping(uint256 => mapping(address => mapping(bytes32 => uint256)))) internal _grants;
    /// @notice Monotonic per identity. Grants written under an earlier nonce are
    /// orphaned, not erased — nothing may ever decrement or re-set this, since
    /// revisiting an old nonce would silently resurrect every grant `revokeAll`
    /// was called to kill.
    mapping(address => uint256) public nonceOf;

    event DelegationGranted(address indexed identity, address indexed agent, bytes32 scope, uint256 validTo);
    event DelegationRevoked(address indexed identity, address indexed agent, bytes32 scope);
    event AllDelegationsRevoked(address indexed identity, uint256 newNonce);

    constructor(DIDRegistry _did) DIDControlled(_did) {}

    function grant(address identity, address agent, bytes32 scope, uint256 validTo)
        external
        onlyIdentityOwner(identity)
    {
        _grants[identity][nonceOf[identity]][agent][scope] = validTo;
        emit DelegationGranted(identity, agent, scope, validTo);
    }

    function revoke(address identity, address agent, bytes32 scope) external onlyIdentityOwner(identity) {
        _grants[identity][nonceOf[identity]][agent][scope] = 0;
        emit DelegationRevoked(identity, agent, scope);
    }

    function revokeAll(address identity) external onlyIdentityOwner(identity) {
        uint256 n = ++nonceOf[identity];
        emit AllDelegationsRevoked(identity, n);
    }

    /// @notice The single check any contract or offchain service needs.
    function isAuthorized(address identity, address agent, bytes32 scope) external view returns (bool) {
        return _grants[identity][nonceOf[identity]][agent][scope] > block.timestamp;
    }
}
