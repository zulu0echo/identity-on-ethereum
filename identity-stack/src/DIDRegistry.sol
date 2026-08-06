// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title DIDRegistry — minimal ERC-1056-style registry (did:ethr).
/// @notice Every address is implicitly a DID. The registry only stores state
/// that deviates from the default (self-owned, no delegates). Offchain DID
/// resolvers reconstruct the DID document from events, walking the `changed`
/// block-pointer chain exactly as ERC-1056 resolvers do.
contract DIDRegistry {
    mapping(address => address) internal _owners;
    /// @notice Pre-authorized agent (e.g. RecoveryModule) allowed to rotate the owner.
    mapping(address => address) public recoveryAgent;
    /// identity => delegateType => delegate => valid-until timestamp
    mapping(address => mapping(bytes32 => mapping(address => uint256))) internal _delegates;
    /// ERC-1056 change pointer: block number of the last event for an identity.
    mapping(address => uint256) public changed;

    event DIDOwnerChanged(address indexed identity, address owner, uint256 previousChange);
    event DIDDelegateChanged(
        address indexed identity, bytes32 delegateType, address delegate, uint256 validTo, uint256 previousChange
    );
    event DIDRecoveryAgentChanged(address indexed identity, address agent, uint256 previousChange);

    error NotIdentityOwner();
    error NotRecoveryAgent();

    modifier onlyOwner(address identity) {
        if (msg.sender != identityOwner(identity)) revert NotIdentityOwner();
        _;
    }

    /// @notice Current controller of `identity`; the identity itself until rotated.
    function identityOwner(address identity) public view returns (address) {
        address owner = _owners[identity];
        return owner == address(0) ? identity : owner;
    }

    function changeOwner(address identity, address newOwner) external onlyOwner(identity) {
        _changeOwner(identity, newOwner);
    }

    /// @notice Recovery path: only the pre-authorized recovery agent may rotate the owner.
    function changeOwnerFrom(address identity, address newOwner) external {
        if (msg.sender != recoveryAgent[identity]) revert NotRecoveryAgent();
        _changeOwner(identity, newOwner);
    }

    function setRecoveryAgent(address identity, address agent) external onlyOwner(identity) {
        recoveryAgent[identity] = agent;
        emit DIDRecoveryAgentChanged(identity, agent, changed[identity]);
        changed[identity] = block.number;
    }

    function addDelegate(address identity, bytes32 delegateType, address delegate, uint256 validity)
        external
        onlyOwner(identity)
    {
        uint256 validTo = block.timestamp + validity;
        _delegates[identity][delegateType][delegate] = validTo;
        emit DIDDelegateChanged(identity, delegateType, delegate, validTo, changed[identity]);
        changed[identity] = block.number;
    }

    function revokeDelegate(address identity, bytes32 delegateType, address delegate)
        external
        onlyOwner(identity)
    {
        _delegates[identity][delegateType][delegate] = block.timestamp;
        emit DIDDelegateChanged(identity, delegateType, delegate, block.timestamp, changed[identity]);
        changed[identity] = block.number;
    }

    function validDelegate(address identity, bytes32 delegateType, address delegate)
        external
        view
        returns (bool)
    {
        return _delegates[identity][delegateType][delegate] > block.timestamp;
    }

    function _changeOwner(address identity, address newOwner) internal {
        _owners[identity] = newOwner;
        emit DIDOwnerChanged(identity, newOwner, changed[identity]);
        changed[identity] = block.number;
    }
}
