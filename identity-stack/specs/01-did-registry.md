# DIDRegistry

**Onchain value case.** Every other component needs a stable answer to "who controls this identifier right now?" that survives key loss and key rotation. Ethereum gives that answer as a single, globally readable, censorship-resistant lookup: `identityOwner(identity)`. Rotate once here, and every registry in the stack (and any third-party contract) follows automatically.

**How it works.** Minimal ERC-1056 (did:ethr). Every address *is* a DID with zero setup and zero gas; the registry only stores deviations from the default (self-owned, no delegates). Offchain resolvers rebuild the DID document from events using the `changed` block-pointer chain, so resolution costs one storage read plus targeted log queries.

## Interface

| Function | Access | Effect |
|---|---|---|
| `identityOwner(identity) → address` | view | Current controller (identity itself until rotated) |
| `changeOwner(identity, newOwner)` | owner | Rotate the controlling key |
| `changeOwnerFrom(identity, newOwner)` | recovery agent | Recovery-path rotation |
| `setRecoveryAgent(identity, agent)` | owner | Pre-authorize a recovery contract |
| `addDelegate(identity, type, delegate, validity)` | owner | Grant expiring key-level delegate |
| `revokeDelegate(identity, type, delegate)` | owner | Expire a delegate now |
| `validDelegate(identity, type, delegate) → bool` | view | Delegate check |

## Storage

`_owners` (address→address, empty = self-owned), `recoveryAgent`, `_delegates` (identity→type→delegate→validTo), `changed` (event chain pointer).

## Invariants

- An identity with no state transitions is controlled by itself; costs nothing.
- Only the current owner (or the pre-set recovery agent) can change ownership; ownership changes are total — the old key retains nothing.
- `changed[identity]` always points at the block of the last event for that identity.

## Standards mapping

ERC-1056 subset; resolvable as `did:ethr`. Delegate types map to DID document verification relationships (`sigAuth` → authentication, `veriKey` → assertionMethod).

## Production path

Use the canonical deployed EthereumDIDRegistry (`0xdca7...`, same address on most networks) instead; this contract exists to make the mechanism legible and to add the explicit `recoveryAgent` hook, which ERC-1056 lacks (it does signed meta-transactions instead).
