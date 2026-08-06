# SchemaRegistry

**Onchain value case.** A credential is only interoperable if issuer and verifier agree on its shape *forever*. Hosting schemas on someone's web server makes every credential's meaning mutable at that host's whim. A content-addressed onchain registry makes schema references immutable, permissionless to create, and identical for every party — the coordination point that lets unrelated issuers issue, and unrelated verifiers verify, the same credential type.

**How it works.** `register(uri, contentHash)` → `schemaId = keccak(uri, contentHash)`. The URI hosts the full definition (W3C VC data model / JSON Schema); the hash pins it; the id is deterministic so the same schema can't be registered twice. No owner, no upgrade, no delete — versioning is registering a new schema.

## Interface

| Function | Access | Effect |
|---|---|---|
| `register(uri, contentHash) → schemaId` | anyone | Immutable registration |
| `schemas(schemaId) → {creator, uri, contentHash, registeredAt}` | view | Lookup |
| `exists(schemaId) → bool` | view | Referenced by IssuerRegistry / AttestationRegistry |

## Invariants

- Registrations are append-only and immutable; a `schemaId` means the same thing in year 10 as in block 1.
- `schemaId` is derivable offline from `(uri, contentHash)`.
- There is no registration cost, length bound, or content check, and deliberately so: any spam control strong enough to matter is a gatekeeper deciding who may define a credential type, which is the thing a permissionless registry exists not to have. The cost of that choice is real — the registry will accumulate junk, and filtering moves to indexers and wallets, which can apply whatever curation they like without anyone's schema becoming unregistrable. Same reasoning applies to `IssuerRegistry` and `VerifierRegistry`.

## Production path

Compare EAS's SchemaRegistry (adds resolver contracts per schema) — resolvers are the natural extension when schemas need onchain validation logic attached.
