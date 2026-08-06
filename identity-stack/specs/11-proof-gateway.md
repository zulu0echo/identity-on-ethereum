# ProofGateway

**Onchain value case.** Verification with no verifier: a Groth16 pairing check replaces the trusted verification service entirely. Any contract — a faucet, a DAO vote, a lending pool — gets "this caller holds a valid, unrevoked credential from issuer X, and hasn't acted in this scope before" as a composable, permissionless primitive. The verifier can't log you, profile you, censor you, or go down, because it's mathematics in consensus, not a company.

**How it works.** Wraps the Semaphore v4 verifier. `verify` checks (1) tree depth bounds, (2) the proof's Merkle root is current-or-recent in CredentialTreeRegistry (this is where ZK *revocation* bites), (3) the Groth16 pairing over public signals `[root, nullifier, hash(message), hash(scope)]` (Semaphore convention: `keccak256 >> 8` into the snark field). `validate` = `verify` + nullifier consumption. `message` binds arbitrary data into the proof — e.g. the claimant address, making proofs front-run-proof: a stolen proof is useless to any other sender.

## Interface

| Function | Access | Effect |
|---|---|---|
| `verify(treeId, proof) → bool` | view | Stateless: root recency + pairing check |
| `validate(treeId, proof)` | anyone | Stateful: verify + consume nullifier under `(caller, scope)` (reverts on any failure) |
| `consumerScope(consumer, scope) → uint256` | pure | The namespace `validate` writes under for that caller |

`Proof = {merkleTreeDepth, merkleTreeRoot, nullifier, message, scope, points[8]}` — exactly Semaphore v4's proof shape, so any Semaphore wallet/prover tooling works unchanged.

## Invariants

- A proof valid at time T against root R stays valid only while R is within its tree's root window.
- `validate` is atomic: no nullifier is consumed for a failed proof, no valid proof lands twice in the same `(consumer, scope)`.
- Nullifiers are namespaced per *calling contract*, not per gateway. `validate` is permissionless and the gateway itself never inspects `message`, so a gateway-wide namespace would be a griefing vector: an attacker copies a pending consumer call out of the mempool, front-runs it with a direct `validate`, and burns the nullifier. The honest call then reverts — and since nullifiers are deterministic per (secret, scope), that holder is locked out of the scope *permanently*, with the attacker gaining nothing but the exclusion. Namespacing by `msg.sender` confines any such burn to the attacker's own namespace.
- A consequence worth stating: two applications that pick the same `scope` value do **not** share a nullifier space. Wanting one shared "one action per person" namespace across several applications means routing them through a common consumer contract.
- Consumers *must* check `message`/`scope` semantics themselves (see GatedAirdrop) — the gateway proves credential validity, not application intent.

## Production path

Multiple circuit support (disclosure proofs, range proofs — "over 18" — beyond membership), verifier upgradability behind governance, aggregated/recursive proofs for batch verification.
