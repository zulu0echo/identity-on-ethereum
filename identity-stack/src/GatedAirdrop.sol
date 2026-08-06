// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ProofGateway} from "./ProofGateway.sol";
import {CredentialTreeRegistry} from "./CredentialTreeRegistry.sol";
import {TrustRegistry, ROLE_ISSUER} from "./TrustRegistry.sol";

/// @title GatedAirdrop — the composability payoff, in ~40 lines.
/// @notice One claim per *person* (not per address): requires a ZK proof of
/// holding a valid credential from an issuer that a chosen authority has
/// accredited for a specific schema. The proof's `message` must be the
/// claimant address (front-running protection) and its `scope` the campaign
/// id (nullifier namespace = one claim each). No PII, no offchain verifier,
/// no allowlist ops — just calls into the identity stack.
contract GatedAirdrop {
    ProofGateway public immutable gateway;
    CredentialTreeRegistry public immutable trees;
    TrustRegistry public immutable trust;

    address public immutable trustedAuthority;
    bytes32 public immutable requiredSchema;
    uint256 public immutable treeId;
    uint256 public immutable campaignScope;

    mapping(address => uint256) public claims;

    event Claimed(address indexed recipient, uint256 nullifier);

    error WrongScope();
    error ProofNotBoundToCaller();
    error IssuerNotAccredited();

    constructor(
        ProofGateway _gateway,
        TrustRegistry _trust,
        address _trustedAuthority,
        bytes32 _requiredSchema,
        uint256 _treeId,
        uint256 _campaignScope
    ) {
        gateway = _gateway;
        trees = _gateway.trees();
        trust = _trust;
        trustedAuthority = _trustedAuthority;
        requiredSchema = _requiredSchema;
        treeId = _treeId;
        campaignScope = _campaignScope;
    }

    function claim(ProofGateway.Proof calldata proof) external {
        if (proof.scope != campaignScope) revert WrongScope();
        if (proof.message != uint256(uint160(msg.sender))) revert ProofNotBoundToCaller();

        (address issuer,) = trees.meta(treeId);
        if (!trust.isAccredited(trustedAuthority, issuer, ROLE_ISSUER, requiredSchema)) {
            revert IssuerNotAccredited();
        }

        // Reverts on invalid proof, stale root, or reused nullifier.
        gateway.validate(treeId, proof);

        claims[msg.sender] += 1;
        emit Claimed(msg.sender, proof.nullifier);
    }
}
