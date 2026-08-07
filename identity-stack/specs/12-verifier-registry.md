---
slug: 12
title: 12/VERIFIER-REGISTRY
name: Verifier Accountability Registry
status: draft
category: Standards Track
layer: Accountability & Economics
tags: verifier, accountability, relying-party, eidas, data-minimisation
source: src/VerifierRegistry.sol
requires: 01/DID-REGISTRY
---

# Verifier Accountability Registry Specification

# Abstract

The Verifier Accountability Registry is the issuer directory pointed the other way: it
makes the parties that collect data discoverable, accreditable, and accountable. It is
structurally the mirror of 05/ISSUER-REGISTRY — permissionless
self-registration of an identity with a metadata URI and an active flag. Combined with
ROLE_VERIFIER accreditation in 06/TRUST-REGISTRY and a published policy in
13/POLICY-REGISTRY, it lets a wallet enforce a rule today's ecosystems cannot express:
do not present credentials to a verifier nobody vouches for.

# Status of This Document

This document is a working specification derived from a reference implementation. It has not been reviewed or ratified by any standards body and is distributed for evaluation and discussion. It follows established specification conventions — requirement keywords, security and privacy considerations, registry definitions, and separated normative and informative references — so that reviewers can read it against a familiar structure.

Changes are made by pull request against the source repository. The reference implementation in `src/VerifierRegistry.sol` and its test suite are normative where this prose is ambiguous.

# Copyright Notice

This specification is published under the MIT license of the repository that contains it (see `LICENSE`). Contributors retain copyright in their contributions and license them under those terms.

# Conventions and Terminology

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD
NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as
described in [RFC2119] and [RFC8174] when, and only when, they appear in all
capitals, as shown here.

## Terminology

- **Verifier / relying party.** The party requesting and collecting credential data.
- **Composite rule.** Registered ∧ accredited ∧ acceptable policy — the wallet's
  pre-presentation check.

# Introduction

Identity systems have always vetted the holder exhaustively while the party collecting the
data stayed anonymous and unaccountable — identity's oldest asymmetry. The eIDAS 2.0
analyses (see [References](#references)) make relying-party registration a central
regulatory instrument precisely because over-collection becomes attributable once the
collector is a registered, identifiable party. This component is that instrument in
shared-infrastructure form, with no single administrator to capture.

Its power is compositional: registration alone asserts nothing (as with issuers), but
combined with accreditation and a published disclosure policy it gives wallets a mechanical
pre-presentation check.

# Specification

## System Requirements

An implementation MUST provide:

- One-time self-registration of a verifier identity with a metadata URI.
- An owner-controlled active flag.
- A predicate reporting whether a verifier is registered and active.
- Resolution of "owner" through 01/DID-REGISTRY.

## Data Structures

```text
Verifier  { string metadataURI; uint64 registeredAt; bool active }
verifiers: mapping(address => Verifier)
```

## Interface

| Function | Access | Effect |
|---|---|---|
| `register(address identity, string metadataURI)` | identity owner | One-time self-registration; reverts `AlreadyRegistered`. |
| `setActive(address identity, bool active)` | identity owner | Pause or resume; reverts `NotRegistered` if absent. |
| `isActive(address identity) → bool` | view | `registered ∧ active` — both conjuncts checked explicitly. |

**Errors.** `AlreadyRegistered`, `NotRegistered`. **Events.** `VerifierRegistered`,
`VerifierStatusChanged`.

## Protocol Flow

1. A verifier calls `register(identity, metadataURI)` and seeks `ROLE_VERIFIER`
   accreditation in 06/TRUST-REGISTRY and publishes a policy in 13/POLICY-REGISTRY.
2. Before releasing a presentation, a wallet evaluates the composite rule:
   **registered ∧ accredited by a root the holder accepts ∧ operating under a policy the
   holder accepts.**

# Invariants

- **Three separable concerns, three contracts.** Registration is permissionless here;
  endorsement is 06/TRUST-REGISTRY's; disclosure policy is 13/POLICY-REGISTRY's.
- **Honest predicate.** `isActive` checks registration explicitly, so "never registered"
  and "registered then paused" are not conflated.
- **Control follows the identifier** via `DIDRegistry.identityOwner`.

# Security and Privacy Considerations

## Threat model

- **Registration theatre.** A registered verifier is not a trustworthy one; security is in
  accreditation and in wallets enforcing it. An interface that renders "registered" as a
  trust badge recreates the confusion this design removes.
- **Root capture.** Whoever's verifier-accreditation roots are widely adopted becomes a
  pressure point; plural roots and published policies are the mitigation, as in
  06/TRUST-REGISTRY.
- **Enforcement gap.** The check protects only holders whose wallets perform it. Until
  wallet behaviour is standard, accountability is opt-in; a deployment SHOULD treat
  wallet-side enforcement as part of its own scope, not an externality.

## Privacy

The registry describes verifiers (institutions), not natural persons; no personal data is
stored. Its privacy value is indirect: it enables the wallet-side refusal that prevents
personal data leaving the holder in the first place.

# Interoperability

The structure maps closely onto eIDAS relying-party registration requirements, with the
register maintained by no single administrator and available to every jurisdiction on
equal terms.

# Implementation Notes and Production Path

- **Register and seek accreditation before asking for anything**; being checkable is the
  price of asking, and becomes a commercial asset.
- **Ship the wallet-side rule** (registered ∧ accredited ∧ acceptable policy) in any wallet
  you control or procure — the component is inert without it.
- **Future work:** a single wallet-facing helper folding registration, accreditation, and
  policy into `shouldIPresentTo(verifier, schema, myRoots[]) → bool`.

# Registry Considerations

This document defines no shared value registries. Registries used across the specifications are defined in 00/REGISTRIES.

# Normative References

- [RFC2119] Bradner, S., "Key words for use in RFCs to Indicate Requirement Levels", RFC 2119, March 1997 — https://www.rfc-editor.org/rfc/rfc2119
- [RFC8174] Leiba, B., "Ambiguity of Uppercase vs Lowercase in RFC 2119 Key Words", RFC 8174, May 2017 — https://www.rfc-editor.org/rfc/rfc8174

# Informative References

- Self-Sovereign Identity and eIDAS 2.0: An Analysis of Control, Privacy, and Legal Implications, arXiv:2601.19837 — https://arxiv.org/pdf/2601.19837
- The impact of zero-knowledge proofs on data minimisation compliance of digital identity wallets, Internet Policy Review — https://policyreview.info/articles/analysis/impact-zero-knowledge-proofs
- SoK: Delegation and Revocation, the Missing Links in the Web's Chain of Trust, arXiv:1906.10775 — https://arxiv.org/pdf/1906.10775
