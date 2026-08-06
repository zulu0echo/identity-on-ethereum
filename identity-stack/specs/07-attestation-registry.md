---
slug: 07
title: 07/ATTESTATION-REGISTRY
name: Public Claims (Attestation) Registry
status: draft
category: Standards Track
layer: Trust
tags: attestations, public-claims, eas, transparency, non-personal-data
source: src/AttestationRegistry.sol
requires: 01/DID-REGISTRY, 04/SCHEMA-REGISTRY
---

# Public Claims Registry Specification

# Change Process

This document specifies one component of the identity-stack proof of concept, derived from
`src/AttestationRegistry.sol`. That implementation and its test suite are normative where
this prose is ambiguous.

# Language

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD
NOT", "RECOMMENDED", "MAY", and "OPTIONAL" are to be interpreted as described in
[RFC 2119](https://www.ietf.org/rfc/rfc2119.txt).

# Abstract

The Public Claims Registry records **claims that are public by nature and contain no
personal data** — an organisation holds a licence, a contract passed an audit, an address
is a registered market maker — in the clear, on-chain. Each attestation has a unique id and
a single validity predicate, `isValid(uid)`, combining existence, non-revocation, and
non-expiry, which any contract can gate on directly. It is an EAS-shaped minimal registry.

# Motivation

Not every claim needs the privacy path. When a claim is already public, proof machinery
adds cost without adding protection, and the transparency-log tradition applies directly:
put the claim where everyone can read it and no one can quietly amend it, so any contract
or indexer sees the same state with no presentation protocol involved.

The institutional discipline here is the **boundary**, not the mechanism. The moment a
claim can identify a natural person it belongs on the privacy-preserving path
(09/CREDENTIAL-TREE-REGISTRY) instead, because a public ledger is permanent and personal
data placed on one cannot be withdrawn, corrected, or erased — a compliance failure under
data-protection law and an ethical one regardless. The specification enforces this as
policy; no contract can enforce it, which is exactly why it is stated so plainly.

# Specification

## System Requirements

An implementation MUST provide:

- Issuer-authored attestations referencing an existing schema, with an optional expiry and
  a claim body.
- A unique identifier per attestation.
- Issuer-only revocation, restricted to the original issuer.
- A validity predicate that is a pure function of on-chain state.

## Data Structures

```text
Attestation { address issuer; address subject; bytes32 schemaId;
              uint64 issuedAt; uint64 expiry; uint64 revokedAt; bytes data }
              // expiry == 0 means no expiry; data is the schema-encoded claim body

attestations: mapping(bytes32 => Attestation)   // keyed by uid
_nonce:       uint256                            // disambiguates otherwise-identical attestations
```

The identifier is `uid = keccak256(abi.encode(issuer, subject, schemaId, data,
block.timestamp, _nonce++))`.

## Interface

| Function | Access | Effect |
|---|---|---|
| `attest(address issuer, address subject, bytes32 schemaId, uint64 expiry, bytes data) → bytes32 uid` | issuer owner | Create an attestation; the schema MUST exist. |
| `revoke(address issuer, bytes32 uid)` | issuer owner | Revoke; the caller MUST be the attestation's original issuer. |
| `isValid(bytes32 uid) → bool` | view | `exists ∧ ¬revoked ∧ ¬expired`. |
| `attestations(bytes32 uid) → Attestation` | view | Full record, including `data`. |

**Errors.** `UnknownSchema`, `UnknownAttestation`, `NotAttestationIssuer`. **Events.**
`Attested(uid, issuer, subject, schemaId, expiry)`, `AttestationRevoked(uid, issuer)`.

## Protocol Flow

1. An issuer calls `attest(...)` referencing a registered schema and records the `uid`.
2. A consuming contract gates behaviour on `require(attestations.isValid(uid))`.
3. If circumstances change, the original issuer calls `revoke(issuer, uid)`; `isValid`
   returns false from the next block, while the record itself remains readable.

# Invariants

- **Sole revoker.** Only the original issuing identity can revoke its attestation.
- **State-pure validity.** Validity is a pure function of on-chain state — no oracle, no
  off-chain fetch.
- **No personal data.** `data` is public forever; anything person-identifying MUST NOT be
  placed here and belongs on the privacy path (09/CREDENTIAL-TREE-REGISTRY).

# Security and Privacy Considerations

## Threat model

- **Personal data by accident (dominant risk).** A claim body that identifies a person,
  placed on a permanent public record, cannot be un-published; data-protection erasure
  rights cannot be honoured retroactively. The boundary MUST be enforced at issuance
  review, not assumed.
- **Defamation / spam surface.** Anyone can attest anything about any subject address.
  Consumers MUST filter by issuer (via 06/TRUST-REGISTRY); an unendorsed attestation is
  noise by default and interfaces SHOULD render it as such.
- **Revocation semantics.** A revoked attestation remains readable — history is not erased
  — so consumers MUST check `isValid`, never mere existence.

## Privacy

By construction the registry is for non-personal claims only. The privacy control is the
issuance-side boundary; there is no cryptographic privacy here, which is the entire reason
the ZK path exists as a separate component.

# Interoperability

The attestation shape follows the Ethereum Attestation Service (EAS) model. In production
an implementer SHOULD use EAS itself — deployed, indexed, and tooled — with this minimal
registry serving to keep the proof of concept's trust model legible end to end.

# Implementation Notes and Production Path

- **Adopt EAS in production**; the schema-resolver and referenced-attestation features are
  the natural next capabilities.
- **Put a human review step** in front of any attestation whose body is free-form — the
  no-personal-data rule needs an owner.
- **Consume through accreditation:** gate on issuer endorsement, never on bare existence.
- **Prefer expiry over revocation** for time-bound claims to avoid stale-cache disputes.

# References

- Certificate Transparency, RFC 6962 — https://datatracker.ietf.org/doc/html/rfc6962
- Blockchain-Based Certificate Transparency and Revocation Transparency, Springer (FC workshops) — https://link.springer.com/chapter/10.1007/978-3-662-58820-8_11
- Verifiable Credentials Overview, W3C — https://www.w3.org/TR/vc-overview/
- RFC 2119 — https://www.ietf.org/rfc/rfc2119.txt

# Glossary

- **Attestation.** A signed public claim by an issuer about a subject, under a schema.
- **uid.** The unique identifier of an attestation.
- **Validity.** Existence and non-revocation and non-expiry, as a pure on-chain predicate.
