---
slug: 09
title: 09/CREDENTIAL-TREE-REGISTRY
name: Private Credentials (Credential Tree) Registry
status: draft
category: Standards Track
layer: Status & Privacy
tags: zero-knowledge, accumulator, merkle-tree, anonymous-credentials, poseidon, revocation
source: src/CredentialTreeRegistry.sol
requires: 01/DID-REGISTRY
---

# Private Credentials Registry Specification

# Abstract

The Private Credentials Registry is the privacy-preserving half of issuance and
revocation. Each issuer maintains one or more accumulators of credential commitments —
Lean Incremental Merkle Trees (the Semaphore v4 accumulator, over the Poseidon hash).
Issuance inserts the holder's identity commitment; revocation zeroes the leaf. A holder
can then prove in zero knowledge that they hold a currently-valid credential from a
specific issuer, against a recent tree root, without revealing which credential. The
chain never sees a credential, a subject, or a plaintext attribute.

# Status of This Memo

This document is a working specification derived from a reference implementation. It is **not** an IETF document and has not been reviewed by any IETF working group; it is distributed for evaluation and discussion. It adopts IETF conventions — BCP 14 requirement keywords, Security and Privacy Considerations, an IANA Considerations section, and split references — so that institutional reviewers can read it against familiar structure, but it claims no IETF status.

Changes are made by pull request against the source repository. The reference implementation in `src/CredentialTreeRegistry.sol` and its test suite are normative where this prose is ambiguous.

# Copyright Notice

This specification is published under the MIT license of the repository that contains it (see `LICENSE`). Contributors retain copyright in their contributions and license them under those terms. A formal IETF submission would instead be governed by the IETF Trust's Legal Provisions (BCP 78) and the rights described in BCP 79; this notice is provided in their place for a non-IETF document.

# Conventions and Terminology

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD
NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as
described in BCP 14 [RFC2119] [RFC8174] when, and only when, they appear in all
capitals, as shown here.

## Terminology

- **Commitment.** A Poseidon hash of a holder-held secret, inserted as a leaf.
- **Accumulator / LeanIMT.** A compact Merkle structure supporting membership proofs.
- **Root-history window (`rootDuration`).** How long a superseded root remains provable —
  equal to the revocation latency.
- **Anonymity set.** The population a proof hides its author among; here, the tree.

# Introduction

This is the component with the deepest research lineage in the stack. Anonymous credentials
descend from the Camenisch–Lysyanskaya constructions, and the revocation problem — how a
holder proves their credential is still valid without identifying it — was answered by the
**dynamic-accumulator** line (Camenisch–Lysyanskaya 2002; Camenisch–Kohlweiss–Soriente
2009): values can be added to and removed from a compact commitment, with membership
provable in zero knowledge and cost independent of the population. The Merkle-tree
instantiation used here, over the SNARK-friendly Poseidon hash (a peer-reviewed design
with actively-maintained cryptanalysis), is that idea in its currently-deployable form.

The literature is equally clear about the operational caveat, which is why it is stated up
front: the mathematics hides a holder among the members of the accumulator, and *no
further*. Anonymity is a population property — measured in the metrics literature by
entropy, not by set size alone — so tree composition is a privacy decision, not an
implementation detail. See [Privacy limits](#privacy-limits).

# Specification

## System Requirements

An implementation MUST provide:

- Issuer-controlled creation of trees, each with a configurable root-history window.
- Issuer-controlled insertion (issuance) and removal (revocation) of commitments.
- A record of every historical root with its first-seen timestamp.
- A root-validity predicate accepting the current root always and historical roots within
  the window.

## Data Structures

```text
TreeMeta { address issuer; uint256 rootDuration }   // rootDuration in seconds

_trees:      mapping(uint256 => LeanIMTData)              // the accumulators
meta:        mapping(uint256 => TreeMeta)
rootSeenAt:  mapping(uint256 => mapping(uint256 => uint256))  // treeId => root => first-seen timestamp
treeCounter: uint256
```

A **commitment** is a Poseidon hash of a secret that never leaves the holder's device (a
Semaphore identity commitment).

## Interface

| Function | Access | Effect |
|---|---|---|
| `createTree(address issuer, uint256 rootDuration) → uint256 treeId` | issuer owner | Create a new tree. |
| `issue(uint256 treeId, uint256 commitment)` / `issueMany(...)` | tree issuer | Insert commitment(s); record the new root's timestamp. |
| `revoke(uint256 treeId, uint256 commitment, uint256[] siblings)` | tree issuer | Zero the leaf, verified on-chain against supplied siblings; record the new root. |
| `currentRoot(uint256 treeId) → uint256` | view | The tree's current root. |
| `isValidRoot(uint256 treeId, uint256 root) → bool` | view | Current root always; historical roots within `rootDuration`. |
| `hasCredential(uint256 treeId, uint256 commitment) → bool` | view | Transparent membership check, for issuer operations — not for holder proofs. |
| `treeSize` / `treeDepth` | view | Bookkeeping. |

**Errors.** `NotTreeIssuer`; a wrong revocation path reverts `WrongSiblingNodes` from the
LeanIMT library. **Events.** `TreeCreated`, `CredentialIssued`, `CredentialsIssued`,
`CredentialRevoked` — each carrying the commitment and the new root.

## Protocol Flow

```mermaid
sequenceDiagram
  participant H as Holder (device)
  participant I as Issuer
  participant T as Credential Tree
  participant GW as Proof Gateway
  H->>I: identity commitment (secret stays on device)
  I->>T: issue(treeId, commitment)
  Note over T: new root recorded
  H->>T: read recent root, build Merkle proof
  H->>GW: ZK membership proof (proves valid, not which)
  I->>T: revoke(treeId, commitment, siblings)
  Note over T: root changes; revoked leaf fails vs fresh roots
```

Issuance:

1. The holder generates a secret on-device and derives a commitment.
2. The issuer calls `issue(treeId, commitment)`.

Proof (performed against 11/PROOF-GATEWAY):

1. The holder builds a Merkle proof of their commitment against a recent root.
2. The holder generates a zero-knowledge membership proof; the gateway checks the root via
   `isValidRoot` and verifies the proof.

Revocation:

1. The issuer calls `revoke(treeId, commitment, siblings)`; the new root excludes the
   commitment, so it fails membership proofs against roots newer than its revocation.

# Invariants

- **Issuer-only mutation.** Only the tree's issuer DID may issue or revoke; control follows
  key rotation.
- **Timestamped roots.** Every root the tree has held is timestamped; `isValidRoot`
  accepts the current root always and a historical root only within `rootDuration`.
- **Enforced revocation.** A revoked commitment cannot re-prove against any root newer than
  its revocation; the LeanIMT update is verified on-chain against supplied siblings.
- **Valid-set, not revoked-set.** The tree holds valid credentials; membership proofs are
  the accumulator's native strength, non-membership proofs are not.

# Security and Privacy Considerations

## Privacy limits

- **The anonymity set is the tree.** A membership proof hides *which* member a holder is,
  among the members that exist. In a tree of three it identifies to one-in-three. Tree
  size is therefore the privacy parameter, and the danger is that the natural way to
  organise trees destroys it: a per-cohort tree ("Q1 2026 KYC applicants, Germany") makes
  membership itself the sensitive attribute. Implementations SHOULD prefer few large trees
  and MUST NOT create a tree whose composition is the disclosure being avoided. The entropy
  view of anonymity (see [References](#references)) is the correct frame: population *and*
  its distribution, not just count.
- **Commitments are public, so lifecycles are linkable.** `CredentialIssued` and
  `CredentialRevoked` carry the commitment in the clear — unavoidably, since off-chain
  provers must rebuild the tree. The chain therefore holds a permanent record that *this
  commitment* was issued at block X and revoked at block Y. The commitment is a stable
  pseudonym: anyone who learns a holder's commitment through any side channel can read that
  holder's entire credential lifecycle retroactively.
- **Revocation timing is a side channel.** A small tree with infrequent writes leaks: one
  revocation in a quiet week correlates with one holder ceasing activity.

## Threat model

- **Small anonymity sets** — the dominant risk, above.
- **Cross-credential linkage.** Reusing one identity secret across issuers links the
  holder's credentials on the public record. Holders SHOULD use a fresh secret per
  credential (supported by the Semaphore identity model; not demonstrated in this PoC).
- **Revocation-latency window.** The root-history window that keeps honest in-flight proofs
  alive is exactly the revocation delay: a withdrawn credential proves successfully until
  the window closes. This is tuned per tree, not eliminated.
- **Hash-function cryptanalysis drift.** SNARK-friendly hashes are younger than SHA-2 and
  under active cryptanalysis; parameter choices SHOULD track the literature, and a
  successor design (Poseidon2) exists when performance demands it.

## Cost

Insertion is O(log n) Poseidon hashes (~250k gas at depth 20). Poseidon in the EVM is the
cost centre; an EVM Poseidon precompile would change the economics of every design in this
class at once.

# Interoperability

**Mandatory-to-implement parameters.** The curve, hash instantiation, signal and identifier encodings, and sizing floors this specification depends on are pinned in [16/CRYPTO-PARAMETERS]. Implementations MUST conform to that profile to interoperate.

Trees are Semaphore v4 groups; the proof shape consumed by 11/PROOF-GATEWAY is stock
Semaphore, so existing prover tooling works unchanged.

# Implementation Notes and Production Path

- **Write tree-composition policy before issuing:** few large trees, never cohort-defined
  ones, with a wallet-enforced floor on population before proving.
- **Issue fresh identity secrets per credential** so holders' credentials cannot be linked
  through commitments.
- **Set the root window per credential class** — minutes for high-stakes access, longer
  where proof-in-flight breakage costs more than revocation delay.
- **Deploy on an L2** for issuance economics, checkpointing roots to L1 where permanence
  demands it; track Poseidon parameter guidance as cryptanalysis evolves.
- **Consider witness-update UX early:** the 2009 accumulator line shows what efficient
  witness maintenance looks like; naive designs push heavy recomputation onto holder
  devices.
- **Future work:** Semaphore v4 directly, batched revocations, ERC-7812-style unified ZK
  registry.

# IANA Considerations

This document requests no IANA actions.

# Normative References

- [RFC2119] Bradner, S., "Key words for use in RFCs to Indicate Requirement Levels", BCP 14, RFC 2119, March 1997 — https://www.rfc-editor.org/rfc/rfc2119
- [RFC8174] Leiba, B., "Ambiguity of Uppercase vs Lowercase in RFC 2119 Key Words", BCP 14, RFC 8174, May 2017 — https://www.rfc-editor.org/rfc/rfc8174
- Poseidon: A New Hash Function for Zero-Knowledge Proof Systems, USENIX Security 2021 — https://www.usenix.org/conference/usenixsecurity21/presentation/grassi

# Informative References

- Dynamic Accumulators and Application to Efficient Revocation of Anonymous Credentials, CRYPTO 2002 — https://cs.brown.edu/people/alysyans/papers/camlys02.pdf
- An Accumulator Based on Bilinear Maps and Efficient Revocation for Anonymous Credentials, PKC 2009 / IACR ePrint 2008/539 — https://eprint.iacr.org/2008/539
- Accumulators with Applications to Anonymity-Preserving Revocation, IACR ePrint 2017/043 — https://eprint.iacr.org/2017/043
- Towards an Information Theoretic Metric for Anonymity, PET 2002 — https://bib.mixnetworks.org/pdf/serjantov2002towards.pdf
