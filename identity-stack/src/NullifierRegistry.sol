// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title NullifierRegistry — shared double-use protection for ZK proofs.
/// @notice A nullifier is deterministic per (identity secret, scope), so
/// consuming it enforces one-action-per-person-per-scope without revealing
/// who acted. Namespaced by consumer contract, so independent gateways can't
/// tread on each other's scopes.
contract NullifierRegistry {
    /// consumer => scope => nullifier => used
    mapping(address => mapping(uint256 => mapping(uint256 => bool))) public used;

    event NullifierConsumed(address indexed consumer, uint256 indexed scope, uint256 nullifier);

    error NullifierAlreadyUsed();

    function consume(uint256 scope, uint256 nullifier) external {
        if (used[msg.sender][scope][nullifier]) revert NullifierAlreadyUsed();
        used[msg.sender][scope][nullifier] = true;
        emit NullifierConsumed(msg.sender, scope, nullifier);
    }
}
