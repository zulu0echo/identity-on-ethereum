// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {DIDRegistry} from "./DIDRegistry.sol";

/// @title RecoveryModule — n-of-m guardian recovery with a timelock.
/// @notice The identity owner configures guardians and sets this module as its
/// recovery agent in DIDRegistry. Guardians can then rotate a lost owner key
/// after `threshold` approvals and a `timelock` delay; the current owner can
/// cancel a malicious attempt during the delay.
contract RecoveryModule {
    struct Config {
        address[] guardians;
        uint128 threshold;
        uint128 timelock;
    }

    struct Attempt {
        address newOwner;
        uint64 readyAt;
        uint64 approvals;
        uint64 round;
    }

    /// @dev An attempt is stale (and replaceable) this long after its timelock matures.
    /// Prevents a single guardian from front-running `execute` with fresh proposals forever.
    uint256 public constant ATTEMPT_TTL = 3 days;

    DIDRegistry public immutable did;

    mapping(address => Config) internal _configs;
    mapping(address => Attempt) public attempts;
    /// identity => round => guardian => approved
    /// @dev `round` only ever increments. Every path that kills an attempt clears
    /// `newOwner` alone and deliberately leaves `round` standing: this mapping is
    /// keyed by it, so resetting the counter would let a guardian's approval from
    /// an old round reappear as an `AlreadyApproved` block on the next one.
    mapping(address => mapping(uint256 => mapping(address => bool))) public approved;

    event RecoveryConfigured(address indexed identity, address[] guardians, uint256 threshold, uint256 timelock);
    event RecoveryProposed(address indexed identity, address newOwner, uint256 readyAt, uint256 round);
    event RecoveryApproved(address indexed identity, address guardian, uint256 approvals);
    event RecoveryExecuted(address indexed identity, address newOwner);
    event RecoveryCancelled(address indexed identity);

    error NotIdentityOwner();
    error NotGuardian();
    error BadConfig();
    error NoActiveAttempt();
    error AlreadyApproved();
    error NotReady();
    error AttemptActive();
    error AttemptExpired();

    constructor(DIDRegistry _did) {
        did = _did;
    }

    modifier onlyIdentityOwner(address identity) {
        if (did.identityOwner(identity) != msg.sender) revert NotIdentityOwner();
        _;
    }

    function configure(address identity, address[] calldata guardians, uint128 threshold, uint128 timelock)
        external
        onlyIdentityOwner(identity)
    {
        if (threshold == 0 || threshold > guardians.length || timelock > 365 days) revert BadConfig();
        _configs[identity] = Config(guardians, threshold, timelock);
        delete attempts[identity].newOwner; // invalidate any in-flight attempt
        emit RecoveryConfigured(identity, guardians, threshold, timelock);
    }

    function guardiansOf(address identity) external view returns (address[] memory) {
        return _configs[identity].guardians;
    }

    function propose(address identity, address newOwner) external {
        if (!_isGuardian(identity, msg.sender)) revert NotGuardian();
        Attempt storage a = attempts[identity];
        // An in-flight attempt can only be replaced once it has gone stale.
        if (a.newOwner != address(0) && block.timestamp <= a.readyAt + ATTEMPT_TTL) revert AttemptActive();
        uint64 round = a.round + 1;
        attempts[identity] =
            Attempt(newOwner, uint64(block.timestamp + _configs[identity].timelock), 1, round);
        approved[identity][round][msg.sender] = true;
        emit RecoveryProposed(identity, newOwner, block.timestamp + _configs[identity].timelock, round);
    }

    function approve(address identity) external {
        if (!_isGuardian(identity, msg.sender)) revert NotGuardian();
        Attempt storage a = attempts[identity];
        if (a.newOwner == address(0)) revert NoActiveAttempt();
        if (approved[identity][a.round][msg.sender]) revert AlreadyApproved();
        approved[identity][a.round][msg.sender] = true;
        a.approvals += 1;
        emit RecoveryApproved(identity, msg.sender, a.approvals);
    }

    function execute(address identity) external {
        Attempt storage a = attempts[identity];
        if (a.newOwner == address(0)) revert NoActiveAttempt();
        if (a.approvals < _configs[identity].threshold || block.timestamp < a.readyAt) revert NotReady();
        if (block.timestamp > a.readyAt + ATTEMPT_TTL) revert AttemptExpired();
        address newOwner = a.newOwner;
        delete attempts[identity].newOwner;
        did.changeOwnerFrom(identity, newOwner);
        emit RecoveryExecuted(identity, newOwner);
    }

    function cancel(address identity) external onlyIdentityOwner(identity) {
        delete attempts[identity].newOwner;
        emit RecoveryCancelled(identity);
    }

    // ponytail: O(n) scan is fine for guardian sets of a handful; swap for a
    // mapping if anyone configures hundreds of guardians.
    function _isGuardian(address identity, address who) internal view returns (bool) {
        address[] storage g = _configs[identity].guardians;
        for (uint256 i = 0; i < g.length; i++) {
            if (g[i] == who) return true;
        }
        return false;
    }
}
