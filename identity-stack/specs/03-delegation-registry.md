---
slug: 03
title: 03/DELEGATION-REGISTRY
name: Scoped Delegation Registry
status: draft
category: Standards Track
layer: Control
tags: identity, delegation, capabilities, authorization, agents, revocation
source: src/DelegationRegistry.sol
requires: 01/DID-REGISTRY
---

# Scoped Delegation Registry Specification

# Abstract

The Delegation Registry records capability-scoped, expiring, revocable grants of
authority: a statement that a given agent MAY act for a given identifier, within a
named scope, until a given time. Any third party — trusting neither the principal nor the
agent — can verify a grant with a single view call, isAuthorized(identity, agent, scope).
A single operation, revokeAll, invalidates every outstanding grant for an identifier in
O(1) by advancing a per-identifier nonce that keys the entire grant mapping.

# Status of This Memo

This document is a working specification derived from a reference implementation. It is **not** an IETF document and has not been reviewed by any IETF working group; it is distributed for evaluation and discussion. It adopts IETF conventions — BCP 14 requirement keywords, Security and Privacy Considerations, an IANA Considerations section, and split references — so that institutional reviewers can read it against familiar structure, but it claims no IETF status.

Changes are made by pull request against the source repository. The reference implementation in `src/DelegationRegistry.sol` and its test suite are normative where this prose is ambiguous.

# Copyright Notice

This specification is published under the MIT license of the repository that contains it (see `LICENSE`). Contributors retain copyright in their contributions and license them under those terms. A formal IETF submission would instead be governed by the IETF Trust's Legal Provisions (BCP 78) and the rights described in BCP 79; this notice is provided in their place for a non-IETF document.

# Conventions and Terminology

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD
NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as
described in BCP 14 [RFC2119] [RFC8174] when, and only when, they appear in all
capitals, as shown here.

## Terminology

- **Grant.** A statement that an agent may act within a scope for an identifier until an
  expiry.
- **Scope.** An application-defined capability hash naming what is authorised.
- **Nonce / revocation epoch.** The per-identifier counter that keys all grants; advancing
  it revokes everything at once.

# Introduction

The near future of identity is agents — increasingly automated ones — acting for people
and institutions. "My agent may present my KYC credential until Friday" must be
answerable by a relying party who trusts no one in the transaction, revocable the instant
something goes wrong, and auditable afterwards.

The object-capability literature, running from 1960s operating-systems research through
today's UCAN and ZCAP frameworks, establishes the right shape: authority should be a
first-class, inspectable object *scoped to a capability*, not an ambient property of
holding a key. Its unsolved problem is revocation. A bearer capability — a signed token —
remains valid in every copy until it expires, and both UCAN and ZCAP require auxiliary
revocation machinery that relying parties must remember to consult. A shared registry
inverts the default: the grant has exactly one authoritative instance, in the place every
relying party already reads, so withdrawal is a single write with global effect in the
next block.

# Specification

## System Requirements

An implementation MUST provide:

- Owner-authorised creation of a grant naming an agent, a scope, and an expiry.
- A single-grant revocation and an all-grants revocation.
- A pure view predicate answering whether a grant is currently authorised.
- Resolution of "owner" through 01/DID-REGISTRY, so control follows key rotation.

## Data Structures

```text
_grants:  mapping(address =>            // identity
            mapping(uint256 =>          //   nonce (revocation epoch)
              mapping(address =>        //     agent
                mapping(bytes32 =>      //       scope (capability hash)
                  uint256))))           //         valid-until (unix seconds)
nonceOf:  mapping(address => uint256)   // current revocation epoch per identity
```

A **scope** is an application-defined capability hash — e.g.
`keccak256("present:kyc-credential")` — *not* a key type. This is the distinction from
the key-typed delegates of 01/DID-REGISTRY one layer below.

## Interface

| Function | Access | Effect |
|---|---|---|
| `grant(address identity, address agent, bytes32 scope, uint256 validTo)` | identity owner | Authorise `agent` for `scope` until `validTo`. |
| `revoke(address identity, address agent, bytes32 scope)` | identity owner | Kill one grant (sets valid-until to 0 under the current nonce). |
| `revokeAll(address identity)` | identity owner | Advance the nonce, orphaning every grant at once. |
| `isAuthorized(address identity, address agent, bytes32 scope) → bool` | view | True iff a grant under the current nonce is unexpired. |

**Events.** `DelegationGranted(identity, agent, scope, validTo)`,
`DelegationRevoked(identity, agent, scope)`, `AllDelegationsRevoked(identity, newNonce)`.

Owner-gated functions MUST revert `NotIdentityOwner` when `msg.sender !=
DIDRegistry.identityOwner(identity)`.

## Protocol Flow

```mermaid
flowchart LR
  P["Identity owner"] -->|"grant(agent, scope, validTo)"| REG["Delegation Registry"]
  P -.->|"revokeAll() advances nonce"| REG
  RP["Relying party"] -->|"isAuthorized(agent, scope)?"| REG
  REG -->|"true / false"| RP
```

Granting and checking:

1. Owner calls `grant(identity, agent, scope, validTo)`.
2. A relying party, before honouring an agent's action, calls `isAuthorized(identity,
   agent, scope)` and proceeds only on `true`.

Incident response:

1. Owner calls `revokeAll(identity)`.
2. From the next block, every prior grant returns `false`, because `isAuthorized` reads
   only under the new nonce.

# Invariants

- **Current-epoch authority.** `isAuthorized` is true only under the current nonce with an
  unexpired grant.
- **Monotonic nonce.** The nonce only ever increases. `revokeAll` *orphans* old grants
  rather than erasing them, so the durability of a revocation depends entirely on this
  one-way property: any future code path that decremented or re-set a nonce would silently
  resurrect every grant it was called to kill. Implementations MUST NOT expose such a
  path.
- **Control follows the identifier.** Authority to grant and revoke resolves through
  `DIDRegistry.identityOwner`, so key rotation carries delegation control with it, and
  grants themselves survive rotation (they attach to the identifier, not the key).

# Security and Privacy Considerations

## Threat model

- **Copied bearer authority (avoided).** The classic failure of signed tokens — valid in
  every copy until expiry — does not arise, because a grant has exactly one authoritative
  instance here.
- **Confused deputy.** An agent holding broad authority can be tricked into exercising it
  for the wrong purpose. Capability scoping — narrow grants naming a single action — is
  the mitigation from the object-capability literature; enforcement still belongs to the
  resource (below).
- **Revocation that resurrects.** Covered by the monotonic-nonce invariant. This is the
  single most important correctness property of the component.
- **Enforcement gap.** This registry *states* authority; it does not enforce it. A relying
  party that never calls `isAuthorized` is not protected. Enforcement is the resource
  holder's responsibility.

## Privacy

The grant graph is public: who authorised which agent, for what, until when. For sensitive
delegations this is itself a disclosure. Hashing the scope reduces what an observer learns
at the cost of third-party legibility; implementations SHOULD hash scopes whose mere
existence is confidential and accept that trade-off knowingly.

# Interoperability

The model aligns with ERC-7710-style delegation frameworks and with the UCAN/ZCAP
capability model at the semantic level: a grant here is the on-chain, instantly-revocable
analogue of a delegated capability. Session keys in smart accounts provide the enforcement
half for account-scoped actions.

# Implementation Notes and Production Path

- **Grant narrowly and expire by default.** Scopes SHOULD name single capabilities; open
  -ended grants SHOULD be an explicit, logged policy exception.
- **Keep enforcement at the resource.** Whatever holds the asset or API MUST check
  `isAuthorized` at time of use.
- **Wire `revokeAll` into incident response** as a rehearsed action, not an engineering
  task discovered under pressure.
- **Future work:** scoped constraint payloads (spend limits, rate limits) as
  scope-parameter structs.

# IANA Considerations

This document is not currently on the IETF stream and requests no IANA actions at this time.

Were it submitted, it would establish a **Capability Scope conventions registry**, replacing the enumeration that is presently defined inline — namely the well-known capability-scope hashes an ecosystem agrees to share. The registry itself — its contents, allocation policy, and initial entries — is defined in [00/REGISTRIES]; the values remain defined inline here until that document is adopted.

# Normative References

- [RFC2119] Bradner, S., "Key words for use in RFCs to Indicate Requirement Levels", BCP 14, RFC 2119, March 1997 — https://www.rfc-editor.org/rfc/rfc2119
- [RFC8174] Leiba, B., "Ambiguity of Uppercase vs Lowercase in RFC 2119 Key Words", BCP 14, RFC 8174, May 2017 — https://www.rfc-editor.org/rfc/rfc8174

# Informative References

- Authorization Capabilities (ZCAP-LD), W3C CCG — https://w3c-ccg.github.io/zcap-spec/
- User Controlled Authorization Network (UCAN) — https://ucan.xyz/specification/
- Capabilities for Distributed Authorization in Information-Centric Networking, arXiv:2308.04140 — https://arxiv.org/pdf/2308.04140
