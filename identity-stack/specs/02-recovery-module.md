---
slug: 02
title: 02/RECOVERY-MODULE
name: Guardian Recovery Module
status: draft
category: Standards Track
layer: Control
tags: identity, recovery, guardians, threshold, timelock, social-recovery
source: src/RecoveryModule.sol
requires: 01/DID-REGISTRY
---

# Guardian Recovery Module Specification

# Change Process

This document specifies one component of the identity-stack proof of concept, derived from
the reference implementation in `src/RecoveryModule.sol`. That implementation and its test
suite are normative where this prose is ambiguous.

# Language

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD
NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as
described in [RFC 2119](https://www.ietf.org/rfc/rfc2119.txt).

# Abstract

The Recovery Module restores control of an identifier whose controlling key has been lost,
without a custodian. The identifier's owner nominates a set of **guardians**, a
**threshold**, and a **timelock**, and authorises this module as the identifier's recovery
agent in [01/DID-REGISTRY](#references). Recovery is then a public, four-step process —
propose, approve to threshold, wait out the timelock, execute — during which the genuine
owner MAY cancel. Because attempts are on-chain events, a hostile recovery is visible to
the owner before it can complete, and the timelock is the window in which they stop it.

# Motivation

"What happens when I lose my key?" is the question on which self-sovereign identity
systems most often fail back to a custodian — reintroducing the very trusted party the
architecture exists to remove, and recreating the account-recovery desk that has
historically been the softest target in institutional systems.

Non-custodial guardian recovery answers the question while keeping three properties that
custodial recovery cannot offer simultaneously: it is **non-custodial** (no party ever
holds the owner's key), **transparent** (every attempt is a public event the owner can
watch and veto), and **programmable** (the threshold and delay are enforced by consensus,
not by a support desk's discretion). Security reviews of deployed guardian-recovery
contracts recur on a small set of flaw families — thresholds checked incompletely,
approvals replayable across attempts, guardian-set changes racing an active recovery, and
denial-of-service by proposal spam. This specification names each and the invariant that
closes it.

# Specification

## System Requirements

An implementation MUST provide:

- Owner-controlled configuration of a guardian set, an approval threshold, and a timelock.
- A guardian-initiated proposal that starts a single active recovery attempt and its
  timelock.
- Threshold accumulation of distinct guardian approvals within one attempt.
- A permissionless execution step that succeeds only when threshold and timelock are both
  satisfied and the attempt has not expired.
- An owner-controlled cancellation available throughout the attempt window.

## Data Structures

```text
Config  { address[] guardians; uint128 threshold; uint128 timelock }
Attempt { address newOwner; uint64 readyAt; uint64 approvals; uint64 round }

_configs:  mapping(address => Config)                                   // per identity
attempts:  mapping(address => Attempt)                                  // per identity
approved:  mapping(address => mapping(uint256 => mapping(address => bool)))
           //           identity              round           guardian

ATTEMPT_TTL = 3 days   // an attempt is stale (replaceable, non-executable) this long after readyAt
```

## Interface

| Function | Access | Effect |
|---|---|---|
| `configure(address identity, address[] guardians, uint128 threshold, uint128 timelock)` | identity owner | Set or replace the guardian configuration; clears any in-flight attempt. |
| `propose(address identity, address newOwner)` | guardian | Start an attempt (counts as its first approval) and its timelock; blocked while a live attempt exists. |
| `approve(address identity)` | guardian | Add one approval to the current attempt's round. |
| `execute(address identity)` | anyone | If approvals ≥ threshold and `block.timestamp ≥ readyAt` and not expired, rotate the owner via `changeOwnerFrom`. |
| `cancel(address identity)` | identity owner | Abort the current attempt. |
| `guardiansOf(address identity) → address[]` | view | The configured guardian set. |

**Errors.** `NotIdentityOwner`, `NotGuardian`, `BadConfig` (threshold zero, threshold >
guardian count, or timelock > 365 days), `NoActiveAttempt`, `AlreadyApproved`, `NotReady`
(below threshold or before `readyAt`), `AttemptActive` (a live attempt cannot be
replaced), `AttemptExpired`.

**Events.** `RecoveryConfigured`, `RecoveryProposed`, `RecoveryApproved`,
`RecoveryExecuted`, `RecoveryCancelled`.

## Protocol Flow

1. **Configure (owner).** The owner calls `configure(...)` and, separately, sets this
   module as the identifier's recovery agent in 01/DID-REGISTRY.
2. **Propose (guardian).** A guardian calls `propose(identity, newOwner)`. This opens a
   fresh round, records the proposer's approval, and sets `readyAt = now + timelock`.
3. **Approve (guardians).** Further guardians call `approve(identity)` until `approvals ≥
   threshold`.
4. **Wait.** No execution is possible before `readyAt`. Throughout this window the owner
   MAY `cancel`.
5. **Execute (anyone).** After `readyAt` and before `readyAt + ATTEMPT_TTL`, and with
   threshold met, any caller triggers the rotation.

# Invariants

- **No under-threshold or premature rotation.** Rotation is impossible below `threshold`
  or before `readyAt`.
- **Per-round approvals.** Each proposal starts a fresh round; approvals never carry
  across rounds; a guardian approves a given round at most once.
- **Monotonic round counter.** The `round` counter only ever increments, and every path
  that ends an attempt (`configure`, `cancel`, `execute`) clears `newOwner` only — never
  the counter. This is load-bearing: because `approved` is keyed by round, resetting the
  counter would resurface a guardian's stale approval as an `AlreadyApproved` block on the
  next attempt, locking that guardian out of a legitimate recovery.
- **Reconfiguration voids attempts.** Changing the guardian set invalidates any in-flight
  attempt, defending against config-then-execute races.
- **Pre-authorisation required.** The module can only rotate identifiers that named it via
  `setRecoveryAgent`.
- **Bounded attempt lifetime.** An attempt has a TTL of `readyAt + 3 days`: a live attempt
  cannot be overwritten (so a lone guardian cannot reset the clock forever — the
  propose-spam DoS), and a stale one cannot execute.
- **Bounded timelock.** `timelock ≤ 365 days`, so it cannot overflow the packed `readyAt`.

# Security and Privacy Considerations

## Threat model

- **Guardian collusion at threshold.** A quorum of guardians can take the identifier. The
  timelock converts this from silent theft into a visible, cancellable event — *but only
  if the owner is watching*. Notification infrastructure is therefore part of the security
  boundary, not an optional extra.
- **Approval replay across rounds.** A recurring production flaw. Closed here by
  round-keyed approvals plus the monotonic-round invariant above.
- **Configuration racing an active attempt.** Reconfiguration MUST void the attempt, or a
  compromised owner key could defuse a legitimate recovery and a hostile one could hijack
  a reconfiguration.
- **Proposal-spam denial of service.** Without the attempt TTL, one guardian could
  perpetually re-propose to keep the clock from maturing. The TTL bounds this.
- **Guardian enumeration.** A public guardian set tells an attacker exactly whom to
  socially engineer. The production path is hashed guardian commitments revealed only at
  proposal time.
- **Trivial timelocks.** A zero or near-zero timelock silently voids the cancel defence.
  Implementations SHOULD enforce a floor in policy even though the mechanism permits small
  values.

## Privacy

Guardian identities are public in this proof of concept, which is itself a disclosure
about the owner's social graph. Production deployments SHOULD commit to guardians as
hashes. No other personal data is stored.

# Interoperability

This module recovers the **DID layer** (the identifier's controller). For smart accounts,
ERC-4337 / ERC-7702 social-recovery modules recover the *account key* and are
complementary. An owner MAY use both: account-level recovery for the signing key, this
module for the identifier above it.

# Implementation Notes and Production Path

- **Enforce a minimum timelock** (days, not blocks) and pair it with owner monitoring; the
  cancel window only protects an owner who learns an attempt exists.
- **Commit to guardians as hashes** so the set cannot be enumerated and targeted.
- **Choose guardians across trust domains** so the collusion threshold requires
  compromising unrelated parties, not one household or one employer.
- **Rehearse recovery** before it is needed; the literature reports these schemes fail
  operationally more often than cryptographically.
- **Sweep delegations after recovery.** Rotation restores control but does not undo grants
  a compromised key issued; `revokeAll` in 03/DELEGATION-REGISTRY belongs in the runbook.
- **Future work:** per-guardian weights, recovery of the guardian set itself, and privacy
  for the guardian list.

# References

- Smart Contract-Based Social Recovery Wallet Management Scheme for Digital Assets, ACM RACS 2023 — https://dl.acm.org/doi/10.1145/3564746.3587016
- Identity and Personhood in Digital Democracy, arXiv:2011.02412 — https://arxiv.org/pdf/2011.02412
- ERC-1056 — https://eips.ethereum.org/EIPS/eip-1056
- RFC 2119 — https://www.ietf.org/rfc/rfc2119.txt

# Glossary

- **Guardian.** An address nominated by the owner that may participate in recovery.
- **Threshold.** The minimum number of guardian approvals required to execute.
- **Timelock.** The mandatory delay between proposal and earliest execution.
- **Round.** A single recovery attempt's approval epoch; the key that isolates approvals
  across attempts.
- **Attempt TTL.** The window after `readyAt` during which execution is permitted before
  the attempt goes stale.
