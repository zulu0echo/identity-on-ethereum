# DelegationRegistry

**Onchain value case.** The near future of identity is agents acting for people — "my AI agent may present my KYC credential until Friday". That authorization must be checkable by third parties who trust neither the person nor the agent, revocable instantly, and auditable after the fact. A public registry with expiring, capability-scoped grants gives every relying party the same answer at the same time; revocation propagates in one block, unlike bearer tokens (e.g. signed capability JWTs) which remain valid until expiry wherever they've been copied.

**How it works.** Grants are `(identity, agent, scope) → validTo` where scope is a capability hash, not a key type — that's the difference from ERC-1056 delegates one layer down. `revokeAll` bumps a per-identity nonce that keys the whole grant mapping, killing every outstanding grant in O(1) — the "my agent's been compromised" button.

## Interface

| Function | Access | Effect |
|---|---|---|
| `grant(identity, agent, scope, validTo)` | identity owner (via DIDRegistry) | Authorize agent for scope until validTo |
| `revoke(identity, agent, scope)` | identity owner | Kill one grant |
| `revokeAll(identity)` | identity owner | Nonce bump; kill all grants |
| `isAuthorized(identity, agent, scope) → bool` | view | The single check relying parties need |

## Invariants

- `isAuthorized` is true only under the current nonce with an unexpired grant.
- The nonce is monotonic. `revokeAll` orphans old grants rather than erasing them, so the revocation is only as durable as that one-way property: any future code path that decrements or re-sets a nonce silently resurrects every grant it was called to kill.
- Control follows `DIDRegistry.identityOwner` — key rotation carries delegations' control with it, and grants themselves survive rotation (they attach to the identity, not the key).

## Production path

Scoped constraints (spend limits, rate limits) as scope-parameter structs; ERC-7710-style delegation frameworks; session keys in smart accounts for the enforcement half (this registry is the *statement* of authority; enforcement belongs to the resource).
