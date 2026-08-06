// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {DIDRegistry} from "./DIDRegistry.sol";
import {DIDControlled} from "./DIDControlled.sol";

/// @title PaymentRails — pay-per-verification settlement between verifiers and issuers.
/// @notice The economic loop that keeps issuers issuing: verifiers prepay a
/// balance; each `settle` moves the issuer's posted fee from verifier to
/// issuer and emits a receipt event referencing whatever the verification was
/// (policy id, session hash). No credential data touches the chain here —
/// only the payment and an opaque reference.
contract PaymentRails is DIDControlled {
    mapping(address => uint256) public balanceOf;
    /// issuer => fee in wei per verification (0 = free / not set)
    mapping(address => uint256) public feeOf;

    event Deposited(address indexed account, uint256 amount);
    event Withdrawn(address indexed account, uint256 amount);
    event FeeSet(address indexed issuer, uint256 fee);
    event VerificationSettled(address indexed verifier, address indexed issuer, uint256 fee, bytes32 ref);

    error InsufficientBalance();
    error TransferFailed();
    error FeeTooHigh();
    error NoFeeSet();

    constructor(DIDRegistry _did) DIDControlled(_did) {}

    function setFee(address issuer, uint256 fee) external onlyIdentityOwner(issuer) {
        feeOf[issuer] = fee;
        emit FeeSet(issuer, fee);
    }

    /// @notice Credits any identity's balance (funding someone else is harmless).
    function deposit(address account) external payable {
        balanceOf[account] += msg.value;
        emit Deposited(account, msg.value);
    }

    /// @notice Balances belong to the identity, not the key: control follows the DID,
    /// so rotated/recovered issuers can still withdraw earnings.
    function withdraw(address account, uint256 amount) external onlyIdentityOwner(account) {
        if (balanceOf[account] < amount) revert InsufficientBalance();
        balanceOf[account] -= amount;
        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) revert TransferFailed();
        emit Withdrawn(account, amount);
    }

    /// @notice Called by the verifier after (offchain or onchain) verification.
    /// @param maxFee Caps the charge so an issuer can't front-run with a fee hike.
    function settle(address verifier, address issuer, bytes32 ref, uint256 maxFee)
        external
        onlyIdentityOwner(verifier)
    {
        uint256 fee = feeOf[issuer];
        // Without this, a verifier could emit zero-fee receipts naming any address
        // it likes, and the event log stops being usable as an audit trail.
        if (fee == 0) revert NoFeeSet();
        if (fee > maxFee) revert FeeTooHigh();
        if (balanceOf[verifier] < fee) revert InsufficientBalance();
        balanceOf[verifier] -= fee;
        balanceOf[issuer] += fee;
        emit VerificationSettled(verifier, issuer, fee, ref);
    }
}
