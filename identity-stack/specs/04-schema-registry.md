---
slug: 04
title: 04/SCHEMA-REGISTRY
name: Credential Definitions Registry
status: draft
category: Standards Track
layer: Trust
tags: credentials, schema, content-addressing, interoperability, transparency
source: src/SchemaRegistry.sol
requires: none
---

# Credential Definitions Registry Specification

# Abstract

The Schema Registry publishes permanent, content-addressed definitions of credential
types. The definition document itself lives off-chain; the registry stores its URI, a
content hash pinning it, and a deterministic identifier derived from both. Registration is
permissionless and append-only, so a schemaId means the same thing in year ten as at the
block it was registered, and no host can silently change what a credential type means.

# Status of This Document

This document is a working specification derived from a reference implementation. It has not been reviewed or ratified by any standards body and is distributed for evaluation and discussion. It follows established specification conventions — requirement keywords, security and privacy considerations, registry definitions, and separated normative and informative references — so that reviewers can read it against a familiar structure.

Changes are made by pull request against the source repository. The reference implementation in `src/SchemaRegistry.sol` and its test suite are normative where this prose is ambiguous.

# Copyright Notice

This specification is published under the MIT license of the repository that contains it (see `LICENSE`). Contributors retain copyright in their contributions and license them under those terms.

# Conventions and Terminology

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD
NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as
described in [RFC2119] and [RFC8174] when, and only when, they appear in all
capitals, as shown here.

## Terminology

- **Schema / credential definition.** A description of a credential type's shape.
- **Content hash.** A fingerprint pinning the exact bytes of the off-chain definition.
- **schemaId.** The deterministic identifier `keccak256(abi.encode(uri, contentHash))`.

# Introduction

A credential is interoperable only if issuer and verifier agree on its shape, and agree on
it *permanently*. Hosting a schema on a web server makes every credential ever issued
against it hostage to whoever controls that server: change the file and you retroactively
change the meaning of live credentials, undetectably.

The transparency-log tradition that produced Certificate Transparency establishes the
principle at work here: security-critical reference data should be append-only and
publicly auditable, because the alternative — trusting a host not to alter what it serves —
fails quietly and after the fact. Content addressing makes any alteration *detectable*; a
consensus-backed registry makes the pinned fingerprint *undeletable* and removes the
split-view attack in which a host shows different content to different parties (the core
argument of CertLedger; see [References](#references)).

# Specification

## System Requirements

An implementation MUST provide:

- Permissionless registration of a `(uri, contentHash)` pair.
- A deterministic, offline-computable identifier for each registration.
- Rejection of duplicate registrations.
- A membership predicate other components can gate on.

## Data Structures

```text
Schema  { address creator; string uri; bytes32 contentHash; uint64 registeredAt }
schemas: mapping(bytes32 => Schema)   // keyed by schemaId
```

The identifier is `schemaId = keccak256(abi.encode(uri, contentHash))`, so any party can
compute it offline from the pair and no coordination is required to reference a schema.

## Interface

| Function | Access | Effect |
|---|---|---|
| `register(string uri, bytes32 contentHash) → bytes32 schemaId` | anyone | Immutable registration; reverts if the derived id already exists. |
| `schemas(bytes32 schemaId) → Schema` | view | Full record. |
| `exists(bytes32 schemaId) → bool` | view | Referenced by 05/ISSUER-REGISTRY and 07/ATTESTATION-REGISTRY. |

**Errors.** `register` MUST revert `SchemaAlreadyRegistered` when the derived `schemaId`
is already present. **Events.** `SchemaRegistered(schemaId, creator, uri, contentHash)`.

## Protocol Flow

1. An author publishes the full definition (W3C VC data model / JSON Schema) at a URI and
   computes its content hash.
2. The author calls `register(uri, contentHash)` and records the returned `schemaId`.
3. Issuers and verifiers reference the `schemaId`; a verifier that wants to inspect the
   definition fetches the URI and checks it against the on-chain `contentHash`.

# Invariants

- **Append-only and immutable.** Registrations are never modified or deleted; versioning
  is registering a new schema.
- **Deterministic identity.** `schemaId` is derivable offline from `(uri, contentHash)`,
  and the same pair cannot be registered twice.
- **No gatekeeper.** There is no registration fee, length bound, or content check — see
  the threat model for why.

# Security and Privacy Considerations

## Threat model

- **Mutable reference data (the target).** The attack this component exists to prevent: a
  host altering a definition after issuance, silently changing what every credential of
  that type attests. Content addressing makes the alteration detectable against the pinned
  hash.
- **Split views.** A malicious off-chain host can serve different content to different
  parties. Verifiers MUST check fetched content against the on-chain `contentHash`; the
  ledger provides the single agreed fingerprint.
- **Document availability.** The fingerprint is permanent but the document is off-chain;
  if its host disappears the definition becomes unverifiable in practice. Authors SHOULD
  host on content-addressed storage or mirror it.
- **Spam and squatting.** Permissionless registration accumulates junk, but identifiers
  are content-derived, so nothing valuable can be squatted, and curation is a
  relying-party concern (below).

## The no-gatekeeper decision

There is deliberately no admission control. Any spam control strong enough to matter would
make some party the arbiter of which credential types may exist — precisely the capture
risk a shared registry exists to avoid. The accepted cost is that the registry accumulates
unused entries; the mitigation is that indexers and wallets curate what they recognise,
without anyone's schema becoming unregistrable. The same reasoning governs
05/ISSUER-REGISTRY and 12/VERIFIER-REGISTRY. No personal data is stored.

# Interoperability

**Mandatory-to-implement parameters.** The curve, hash instantiation, signal and identifier encodings, and sizing floors this specification depends on are pinned in [16/CRYPTO-PARAMETERS]. Implementations MUST conform to that profile to interoperate.

The URI SHOULD point at a W3C Verifiable Credentials data-model / JSON Schema document, so
existing verifier tooling can consume registered types unchanged.

# Implementation Notes and Production Path

- **Host on content-addressed storage** (or mirror), so availability matches the
  permanence of the fingerprint.
- **Treat definitions as write-once** organisationally: version by new registration and
  record supersession inside the definition document.
- **Compare EAS's SchemaRegistry**, which attaches per-schema resolver contracts — the
  natural extension when a schema needs on-chain validation logic.
- **Budget for curation:** run or subscribe to an indexer that lists recognised
  definitions.

# Registry Considerations

This document defines no shared value registries. Registries used across the specifications are defined in 00/REGISTRIES.

# Normative References

- [RFC2119] Bradner, S., "Key words for use in RFCs to Indicate Requirement Levels", RFC 2119, March 1997 — https://www.rfc-editor.org/rfc/rfc2119
- [RFC8174] Leiba, B., "Ambiguity of Uppercase vs Lowercase in RFC 2119 Key Words", RFC 8174, May 2017 — https://www.rfc-editor.org/rfc/rfc8174
- Verifiable Credentials Overview, W3C — https://www.w3.org/TR/vc-overview/

# Informative References

- Certificate Transparency, RFC 6962 — https://datatracker.ietf.org/doc/html/rfc6962
- CertLedger: A New PKI Model with Certificate Transparency Based on Blockchain, arXiv:1806.03914 — https://arxiv.org/pdf/1806.03914
