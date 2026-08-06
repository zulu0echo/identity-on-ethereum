---
slug: 05
title: 05/ISSUER-REGISTRY
name: Issuer Directory
status: draft
category: Standards Track
layer: Trust
tags: credentials, issuer, discovery, directory, self-registration
source: src/IssuerRegistry.sol
requires: 01/DID-REGISTRY, 04/SCHEMA-REGISTRY
---

# Issuer Directory Specification

# Change Process

This document specifies one component of the identity-stack proof of concept, derived from
`src/IssuerRegistry.sol`. That implementation and its test suite are normative where this
prose is ambiguous.

# Language

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD
NOT", "RECOMMENDED", "MAY", and "OPTIONAL" are to be interpreted as described in
[RFC 2119](https://www.ietf.org/rfc/rfc2119.txt).

# Abstract

The Issuer Directory is a **permissionless, self-registered directory of issuers**, each
of which MAY publicly declare the credential types it issues. It is deliberately a
directory of *discovery and commitment only*: a directory entry asserts nothing about
whether an issuer should be believed. Endorsement is a separate concern, handled by
[06/TRUST-REGISTRY](#references). The composite predicate `issuesSchema(issuer, schemaId)`
returns true only when the issuer is registered, active, and has declared that schema.

# Motivation

Verifiers need to discover issuers and pin their identity over time; issuers need a public
place to commit to what they issue. Doing this on-chain makes the directory
key-rotation-proof (entries follow the DID, not the key) and globally consistent.

The design's central decision — separating discovery from endorsement — is a direct
response to the PKI literature's longest-running lesson, systematised in *SoK: Delegation
and Revocation, the Missing Links in the Web's Chain of Trust*: whoever controls admission
to a directory controls participation, and becomes a target. Conflating "listed" with
"trusted" produced both capture and brittleness in the web PKI. Here, listing is open to
anyone and means only that an institution has said something about itself; belief is
layered on separately. The schema declarations then give relying parties a cheap
consistency check: a credential claiming to come from an issuer that never declared its
type is anomalous by construction.

# Specification

## System Requirements

An implementation MUST provide:

- One-time self-registration of an issuer identity with a metadata URI.
- An owner-controlled active flag.
- Owner-controlled declaration and withdrawal of schemas the issuer issues.
- A composite predicate combining registration, active status, and declaration.
- Resolution of "owner" through 01/DID-REGISTRY.

## Data Structures

```text
Issuer          { string metadataURI; uint64 registeredAt; bool active }
issuers:        mapping(address => Issuer)
declaredSchemas: mapping(address => mapping(bytes32 => bool))   // issuer => schemaId => declared
```

## Interface

| Function | Access | Effect |
|---|---|---|
| `register(address identity, string metadataURI)` | identity owner | One-time self-registration. Reverts `AlreadyRegistered` if present. |
| `setActive(address identity, bool active)` | identity owner | Pause or resume (e.g. during a key incident). Reverts `NotRegistered` if absent. |
| `declareSchema(address identity, bytes32 schemaId)` | identity owner | Commit to issuing a schema; the schema MUST exist in 04/SCHEMA-REGISTRY. |
| `withdrawSchema(address identity, bytes32 schemaId)` | identity owner | Withdraw a declaration. |
| `issuesSchema(address identity, bytes32 schemaId) → bool` | view | `registered ∧ active ∧ declared`. |

**Errors.** `NotRegistered`, `AlreadyRegistered`, `UnknownSchema`. **Events.**
`IssuerRegistered`, `IssuerStatusChanged`, `SchemaDeclared`, `SchemaWithdrawn`.

## Protocol Flow

1. An issuer calls `register(identity, metadataURI)`.
2. The issuer calls `declareSchema(identity, schemaId)` for each type it issues.
3. A wallet receiving a credential checks `issuesSchema(issuer, schemaId)` and flags
   credentials from issuers that never declared the type.
4. During a key incident the issuer calls `setActive(identity, false)` to pause visibly.

# Invariants

- **Registration asserts no trust.** This registry is discovery and commitment,
  deliberately separated from endorsement (06/TRUST-REGISTRY).
- **Declared schemas exist.** A declaration requires the schema to be present in
  04/SCHEMA-REGISTRY.
- **Composite honesty.** `issuesSchema` checks registration explicitly, not merely the
  active flag, so "never registered" and "registered then paused" are not conflated.
- **Control follows the identifier** via `DIDRegistry.identityOwner`.

# Security and Privacy Considerations

## Threat model

- **Impersonation at registration.** Anyone can put any name in metadata. The directory
  binds *identifiers*, not legal names; binding a real-world institution to its identifier
  is 06/TRUST-REGISTRY's job. Wallets MUST treat unaccredited metadata as unverified.
- **Directory capture (structurally absent).** There is no admission decision to capture —
  the design's central claim, inherited from 04/SCHEMA-REGISTRY's no-gatekeeper stance.
- **Stale or abandoned entries.** Self-registration means nobody prunes. The active flag
  and declaration withdrawal give issuers a clean exit; relying parties SHOULD treat
  long-dormant entries with suspicion as policy.
- **Metadata as attack surface.** URIs can dangle or be re-pointed. Anything relied upon
  SHOULD be content-hashed, as in 04/SCHEMA-REGISTRY.

## Privacy

Entries and declarations are public. The directory holds no personal data; it describes
institutions, not natural persons.

# Interoperability

Metadata SHOULD follow issuer-DID-document conventions (service endpoints), enabling
resolvers to discover an issuer's presentation and status endpoints from its entry.

# Implementation Notes and Production Path

- **Register early and declare precisely** — the declaration is a free consistency check
  for relying parties.
- **Never render "listed" as "trusted"** in any interface; the discovery/endorsement
  separation only protects users if wallets show it honestly.
- **Pin metadata by content hash** and host on content-addressed storage.
- **Future work:** fee or stake as spam control, and enumeration events for indexers.

# References

- SoK: Delegation and Revocation, the Missing Links in the Web's Chain of Trust, arXiv:1906.10775 — https://arxiv.org/pdf/1906.10775
- Certificate Transparency, RFC 6962 — https://datatracker.ietf.org/doc/html/rfc6962
- Methods for Decentralized Identities, IACR ePrint 2021/1087 — https://eprint.iacr.org/2021/1087
- RFC 2119 — https://www.ietf.org/rfc/rfc2119.txt

# Glossary

- **Directory entry.** A self-registered issuer record: metadata URI, registration time,
  active flag.
- **Declaration.** An issuer's public commitment that it issues a given schema.
- **Discovery vs. endorsement.** Being findable (here) versus being vouched for
  (06/TRUST-REGISTRY).
