# IssuerRegistry

**Onchain value case.** Verifiers need to discover issuers and pin their identity over time; issuers need a public place to commit to what they issue. Doing this onchain makes the directory permissionless (no gatekeeper decides who may *call themselves* an issuer — trust is layered on separately by TrustRegistry), globally consistent, and key-rotation-proof (entries follow the DID, not the key).

**How it works.** An issuer self-registers `(identity, metadataURI)` and declares the schemas it issues — the "issuer schemas" use case: a public, timestamped commitment that lets wallets warn when a credential arrives from an issuer that never declared its schema, and lets verifiers enumerate who claims to issue what. `issuesSchema(issuer, schema)` is the composite check: registered ∧ active ∧ declared.

## Interface

| Function | Access | Effect |
|---|---|---|
| `register(identity, metadataURI)` | identity owner | One-time self-registration |
| `setActive(identity, bool)` | identity owner | Pause/unpause (e.g. key incident) |
| `declareSchema(identity, schemaId)` | identity owner | Commit to issuing a schema (must exist in SchemaRegistry) |
| `withdrawSchema(identity, schemaId)` | identity owner | Withdraw the commitment |
| `issuesSchema(identity, schemaId) → bool` | view | registered ∧ active ∧ declared |

## Invariants

- Registration says nothing about trustworthiness — that's TrustRegistry's job. This registry is *discovery and commitment*, deliberately separated from *endorsement*.
- Declared schemas must exist in SchemaRegistry.
- Control follows `DIDRegistry.identityOwner`.

## Production path

Metadata standards (issuer DID document service endpoints), fee/stake for registration as spam control, enumeration events for indexers.
