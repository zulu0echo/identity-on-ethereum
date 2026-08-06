# TrustRegistry

**Onchain value case.** The hardest identity question isn't "is this credential valid?" but "why should I believe this issuer?" Today that's answered by closed, jurisdiction-bound trusted lists (eIDAS LOTL, DNS roots). Onchain, accreditation becomes an open graph: any authority can vouch for any subject, every relying party picks its own roots, and revocation of trust propagates to every verifier in one block. No single root of trust — plural, inspectable, composable roots.

**How it works.** An accreditation is `(authority, subject, role, schemaId) → {issuedAt, expiry, revokedAt, uri}`, written only by the authority's DID owner. `ROLE_ISSUER` / `ROLE_VERIFIER` accredit the two ends of the trust triangle with the same primitive — this one contract implements the "verified verifiers" use case too. `checkChain(path, role, schema)` walks multi-hop hierarchies: intermediate links must hold `ROLE_ACCREDITOR`, the last link the target role — eIDAS-style hierarchies become one view call.

## Interface

| Function | Access | Effect |
|---|---|---|
| `accredit(authority, subject, role, schemaId, expiry, uri)` | authority owner | Issue/refresh accreditation |
| `revoke(authority, subject, role, schemaId)` | authority owner | Revoke (timestamped, permanent record) |
| `isAccredited(authority, subject, role, schemaId) → bool` | view | issued ∧ ¬revoked ∧ ¬expired |
| `checkChain(path[], role, schemaId) → bool` | view | Walk root → accreditor(s) → subject |

## Invariants

- Anyone can accredit anyone: authority is meaningless until a relying party *chooses* it as a root. Trust is in the reader, not the registry.
- Revocations leave a permanent timestamped trace (audit trail of trust decisions).
- Chain validity requires every intermediate hop to hold `ROLE_ACCREDITOR` for that schema.

## Production path

Constraint payloads per accreditation (jurisdiction, credential limits) per ToIP Trust Registry protocol; negative attestations (public warnings); indexer-friendly enumeration.
