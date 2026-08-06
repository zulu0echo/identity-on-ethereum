# NullifierRegistry

**Onchain value case.** Anonymity without double-use protection is worthless for identity: an anonymous proof could be replayed forever. A nullifier — deterministic per (holder secret, scope), unlinkable to the holder — consumed in global onchain state gives "one action per person per context" with no registration, no biometrics onchain, and no coordinator. This single mapping is what makes sybil-resistant airdrops, one-person-one-vote, and quadratic funding enforceable.

**How it works.** `consume(scope, nullifier)` sets a bit in `(msg.sender, scope, nullifier)` and reverts if already set. Namespacing by consumer contract means independent gateways can't collide or grief each other's scopes; scope separates contexts so the same credential yields *different, unlinkable* nullifiers per context (voting in poll A doesn't link to claiming airdrop B).

## Interface

| Function | Access | Effect |
|---|---|---|
| `consume(scope, nullifier)` | any contract (namespaced by caller) | Mark used; revert `NullifierAlreadyUsed` on repeat |
| `used(consumer, scope, nullifier) → bool` | view | Check |

## Invariants

- A (consumer, scope, nullifier) triple transitions false→true exactly once, ever.
- No information about the holder is derivable from a consumed nullifier (guaranteed by the circuit, recorded fact here).
- Caller-namespacing only isolates *direct* callers. A contract that consumes on behalf of many applications — ProofGateway is exactly this — collapses them all into one namespace unless it sub-namespaces the scope itself. It does; see [11](11-proof-gateway.md). Any other shared consumer must do the same, or one application can burn another's nullifiers.

## Production path

This is already near-minimal. The interesting evolution is cross-domain: shared nullifier state across L2s (nullifier bridging is an open research area — spends on two chains must not double-count).
