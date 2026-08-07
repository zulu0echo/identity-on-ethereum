---
slug: 00
title: 00/REGISTRIES
name: Onchain Identity Registries
status: draft
category: Standards Track
layer: Cross-cutting
tags: registries, roles, status-purpose, delegate-type, capability-scope
source: (cross-cutting; no single contract)
requires: 01/DID-REGISTRY, 03/DELEGATION-REGISTRY, 06/TRUST-REGISTRY, 08/STATUS-LIST-REGISTRY
---

# Onchain Identity Registries

# Abstract

This document defines the value registries shared across the identity-stack
specifications. Four enumerations that are presently hardcoded in individual components —
trust roles, status purposes, delegate types, and capability scopes — are collected here as
registries with defined allocation policies, so that independent implementations agree on
the meaning of a value without any party controlling which values may exist.

# Status of This Document

This document is a working specification derived from a reference implementation. It has not
been reviewed or ratified by any standards body and is distributed for evaluation and
discussion.

Changes are made by pull request against the source repository.

# Copyright Notice

This specification is published under the MIT license of the repository that contains it
(see `LICENSE`).

# Conventions and Terminology

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD
NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as
described in [RFC2119] and [RFC8174] when, and only when, they appear in all capitals,
as shown here.

Three registration policies are used in this document:

- **Specification Required.** A registration MUST cite a public document defining the
  value's semantics.
- **Expert Review.** A registration MUST be reviewed by a designated expert before listing.
- **First Come First Served.** A registration is listed on request, subject only to a
  designated expert rejecting duplicates or misleading names.

## Terminology

- **Coordination registry.** A registry whose purpose is to document the agreed meaning of
  well-known values for interoperability. It is **not** admission control.
- **Well-known value.** A value listed here so that independent implementations interpret
  it identically.

# Introduction

The identity stack is deliberately permissionless: on-chain, any party may already write
any role, purpose, delegate type, or capability scope it likes. These registries therefore
serve a different purpose from a conventional protocol registry. They do **not** gate what may
exist — that would contradict the credible-neutrality property the stack is built to
preserve. They exist only so that a value which is *intended to be interoperable* carries an
agreed meaning across wallets, verifiers, and issuers that never coordinated directly.

Two consequences follow, and implementers MUST internalise both:

1. Listing a value here confers no authority and no legitimacy on-chain; an unlisted value
   is equally valid on-chain and simply carries no cross-ecosystem guarantee of meaning.
2. Because the on-chain namespaces are collision-resistant hashes or small enumerations, the
   registries are advisory catalogues, not scarce resources. The allocation policies below
   govern *listing for interoperability*, nothing more.

# Trust Role Registry

Governs the `role` argument of [06/TRUST-REGISTRY]. Values are `bytes32`, computed as
`keccak256(<preimage>)` where `<preimage>` is the UTF-8 role name.

- **Allocation policy:** Specification Required. A registration MUST cite a
  document defining the role's semantics and its treatment in `checkChain`.
- **On-chain namespace:** permissionless; this registry lists well-known roles only.

| Role Name | Preimage (UTF-8) | Value | Semantics | Reference |
|---|---|---|---|---|
| `ROLE_ISSUER` | `ROLE_ISSUER` | `keccak256("ROLE_ISSUER")` | Subject may issue credentials of the referenced schema. | 06/TRUST-REGISTRY |
| `ROLE_VERIFIER` | `ROLE_VERIFIER` | `keccak256("ROLE_VERIFIER")` | Subject may act as a relying party for the referenced schema. | 06/TRUST-REGISTRY, 12/VERIFIER-REGISTRY |
| `ROLE_ACCREDITOR` | `ROLE_ACCREDITOR` | `keccak256("ROLE_ACCREDITOR")` | Subject may appear as an intermediate hop in an accreditation chain. | 06/TRUST-REGISTRY |

# Status Purpose Registry

Governs the `purpose` of a status list in [08/STATUS-LIST-REGISTRY]. Values are a small
unsigned enumeration; `0` is reserved to mean "none / unset".

- **Allocation policy:** Specification Required. A registration MUST declare the
  write semantics (whether a set bit may ever be cleared) and a mapping to the W3C
  `statusPurpose` value, if one exists.

| Purpose | Value | Write Semantics | W3C `statusPurpose` | Reference |
|---|---|---|---|---|
| `Revocation` | 1 | One-way; a set bit MUST NOT be cleared. | `revocation` | 08/STATUS-LIST-REGISTRY |
| `Suspension` | 2 | Reversible; a set bit MAY be cleared to reinstate. | `suspension` | 08/STATUS-LIST-REGISTRY |

# Delegate Type Registry

Governs the `delegateType` of [01/DID-REGISTRY]. This registry **defers to ERC-1056** for
the values themselves and documents only the mapping onto DID-document verification
relationships.

- **Allocation policy:** the value space is that of ERC-1056; this table is a mapping aid,
  not an independent allocation. New mappings require Expert Review.

| Delegate Type | DID-document relationship | Reference |
|---|---|---|
| `veriKey` | `assertionMethod` | ERC-1056 |
| `sigAuth` | `authentication` | ERC-1056 |

# Capability Scope Registry

Governs the `scope` of [03/DELEGATION-REGISTRY]. Values are `bytes32`, computed as
`keccak256(<scope-string>)`. Scopes are application-defined; the vast majority are private
to one ecosystem and need no registration.

- **Allocation policy:** First Come First Served for the human-readable scope
  string, with a Designated Expert resolving obvious duplicates or misleading names. Listing
  is only for scopes intended to be recognised across independently-built wallets.

| Scope String | Value | Meaning | Reference |
|---|---|---|---|
| `present:kyc-credential` | `keccak256("present:kyc-credential")` | Authorises an agent to present a KYC credential on the identity's behalf. Illustrative seed entry. | 03/DELEGATION-REGISTRY |

# Security and Privacy Considerations

## Threat model

- **Registry-as-gatekeeper (rejected by design).** The chief risk is that a coordination
  registry is mistaken for admission control, and its maintainers become a censorship point.
  The allocation policies here govern listing for interoperability only; nothing in these
  registries can prevent an on-chain value from being used. Interfaces MUST NOT present
  "listed here" as "authorised" or "trusted".
- **Semantic squatting.** Under First Come First Served (capability scopes), a party could
  register a misleading name. The Designated Expert exists to reject obvious abuse; the
  deeper mitigation is that scope *meaning* on-chain derives from the resource enforcing it,
  not from this catalogue.
- **Preimage ambiguity.** Two different strings could be intended for the same role/scope.
  Registrations MUST record the exact UTF-8 preimage, and consumers MUST compare the hash,
  never the human name.

## Privacy

These registries hold only value definitions; they contain no personal data and no
per-user state.

# Registry Considerations

This document defines the four registries above — Trust Role, Status Purpose, Delegate Type
and Capability Scope — with the allocation policies stated in each section and the initial
entries listed. They are maintained in this repository. Should the specification series
later be submitted to a standards body, these definitions are intended to transfer intact.

# Normative References

- [RFC2119] Bradner, S., "Key words for use in RFCs to Indicate Requirement Levels", RFC 2119, March 1997 — https://www.rfc-editor.org/rfc/rfc2119
- [RFC8174] Leiba, B., "Ambiguity of Uppercase vs Lowercase in RFC 2119 Key Words", RFC 8174, May 2017 — https://www.rfc-editor.org/rfc/rfc8174
- ERC-1056: Ethereum Lightweight Identity — https://eips.ethereum.org/EIPS/eip-1056

# Informative References

- Bitstring Status List v1.0, W3C (statusPurpose values) — https://www.w3.org/TR/vc-bitstring-status-list/
