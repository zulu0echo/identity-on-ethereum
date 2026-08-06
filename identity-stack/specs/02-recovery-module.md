# RecoveryModule

**Onchain value case.** Identity systems die on the question "what happens when I lose my key?" Custodial recovery reintroduces the trusted party self-sovereign identity was meant to remove. Onchain guardian recovery is non-custodial, transparent (attempts are public events the real owner can see and cancel), and programmable (threshold + timelock are enforced by consensus, not policy).

**How it works.** The identity owner picks guardians (friends' wallets, hardware keys, an institution), a threshold, and a timelock, then sets this module as its `recoveryAgent` in DIDRegistry. Recovery = propose (guardian) → approve to threshold (guardians) → wait out timelock → execute, which calls `changeOwnerFrom`. The current owner can `cancel` at any point in the window — the timelock exists precisely so a compromised guardian set can't rotate silently.

## Interface

| Function | Access | Effect |
|---|---|---|
| `configure(identity, guardians[], threshold, timelock)` | identity owner | Set/replace guardian config; kills in-flight attempts |
| `propose(identity, newOwner)` | guardian | Start attempt (counts as 1 approval), starts timelock; blocked while a live attempt exists |
| `approve(identity)` | guardian | Add approval to current attempt round |
| `execute(identity)` | anyone | If approvals ≥ threshold and timelock passed: rotate owner |
| `cancel(identity)` | identity owner | Abort the attempt |

## Storage

Per identity: `Config {guardians[], threshold, timelock}`, `Attempt {newOwner, readyAt, approvals, round}`, `approved[identity][round][guardian]`.

## Invariants

- Rotation impossible below threshold or before `readyAt`.
- Each proposal starts a fresh round; approvals never carry across rounds; a guardian approves a round at most once.
- The round counter is monotonic and survives cancellation. Every path that kills an attempt (`configure`, `cancel`, `execute`) clears `newOwner` only, on purpose: `approved` is keyed by round, so resetting the counter would make a guardian's stale approval from an old round resurface as an `AlreadyApproved` block on the next one — a guardian could be locked out of recovery by having participated in a previous attempt.
- Reconfiguring guardians invalidates any in-flight attempt (defense against config-then-execute races).
- The module can only rotate identities that pre-authorized it via `setRecoveryAgent`.
- Attempts have a TTL (`readyAt + 3 days`): a live attempt can't be overwritten (a lone guardian can't reset the clock forever — the propose-spam DoS), and a stale one can't execute.
- `timelock` is bounded (≤ 365 days) so it can't overflow the packed `readyAt`.

## Production path

Guardian privacy (hashed guardian commitments à la Argent), per-guardian weights, and recovery of the guardian set itself. For smart accounts, ERC-4337/7702 social recovery modules cover the account key; this module covers the *DID* layer above it.
