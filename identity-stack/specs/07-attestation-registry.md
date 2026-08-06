# AttestationRegistry

**Onchain value case.** The "direct onchain proofs" path: when a claim contains no PII and is public by nature — this contract passed an audit, this address is a registered market maker, this org holds a license — the cheapest, most composable representation is the claim itself, in the clear, onchain. Every contract can consume it with one call; every indexer sees the same state; no proof systems, wallets, or presentation protocols involved.

**How it works.** EAS-shaped minimal attestations: `attest(issuer, subject, schemaId, expiry, data)` returns a `uid`; the schema-encoded claim body lives in `data`. Revocable by the issuing DID, expirable, checkable via `isValid(uid)` — which is exactly the gate other contracts compose on (`require(attestations.isValid(uid))`).

## Interface

| Function | Access | Effect |
|---|---|---|
| `attest(issuer, subject, schemaId, expiry, data) → uid` | issuer owner | Create attestation (schema must exist) |
| `revoke(issuer, uid)` | issuer owner (must be the attestation's issuer) | Revoke |
| `isValid(uid) → bool` | view | exists ∧ ¬revoked ∧ ¬expired |
| `attestations(uid) → Attestation` | view | Full record incl. data |

## Invariants

- Only the original issuing identity can revoke its attestation.
- Validity is a pure function of onchain state — no oracle, no offchain fetch.
- `data` must not contain PII: it is public forever. Anything person-identifying belongs on the ZK path (CredentialTreeRegistry).

## Production path

Use EAS itself — deployed, indexed, tooled. This contract exists so the PoC's trust model is legible end-to-end; the schema resolver and referenced-attestation features of EAS are what you'd want next.
