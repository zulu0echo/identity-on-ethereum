---
slug: 16
title: 16/CRYPTO-PARAMETERS
name: Cryptographic Parameter Profile
status: draft
category: Standards Track
layer: Cross-cutting
tags: mandatory-to-implement, groth16, bn254, poseidon, baby-jubjub, encoding, post-quantum
source: (cross-cutting; profiles src/ProofGateway.sol, src/CredentialTreeRegistry.sol, src/SchemaRegistry.sol, src/StatusListRegistry.sol)
requires: 04/SCHEMA-REGISTRY, 08/STATUS-LIST-REGISTRY, 09/CREDENTIAL-TREE-REGISTRY, 11/PROOF-GATEWAY
---

# Cryptographic Parameter Profile

# Abstract

This document pins the mandatory-to-implement (MTI) cryptographic parameters and byte
encodings on which interoperability of the identity stack depends: the proving system and
curve, the ZK-friendly hash and its instantiation, the holder identity and nullifier
construction, the Merkle accumulator, the public-signal and domain-separation encoding, and
the deterministic identifier encodings. Without a single pinned profile, two honest
implementations cannot produce proofs the other accepts. Every parameter here is a
concrete, ratifiable choice; the rationale, and the known security caveats (notably the
~100-bit security of the mandatory curve and the absence of post-quantum security), are
stated in full.

# Status of This Memo

These parameters are **adopted as the mandatory-to-implement profile** for this proof of concept: the choices below are decided, not open options, and the component specifications reference this profile normatively. It is not an IETF document. An independent cryptographic audit of the circuits and verifying keys is still RECOMMENDED before any production deployment; adoption here fixes the parameters for interoperability, it does not substitute for that review.

Changes are made by pull request against the source repository. Where this profile and the
reference circuits disagree, the circuits and their verifying keys are authoritative and
this document MUST be corrected.

# Copyright Notice

This specification is published under the MIT license of the repository that contains it
(see `LICENSE`). A formal IETF submission would instead be governed by BCP 78 and BCP 79.

# Conventions and Terminology

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD
NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as
described in BCP 14 [RFC2119] [RFC8174] when, and only when, they appear in all capitals,
as shown here.

## Terminology

- **F_r.** The scalar field of the mandatory curve; the field in which all commitments,
  roots, nullifiers, and public signals live.
- **MTI.** Mandatory to implement: a parameter an implementation MUST match to
  interoperate.
- **Domain separation.** Ensuring hash inputs for distinct purposes cannot collide by
  binding a purpose-specific prefix or construction.

# Introduction

The four cryptographic specifications (04, 08, 09, 11) name their primitives but did not,
before this profile, pin them to the bit. An implementer could read "Groth16", "Poseidon",
"LeanIMT" and still build something that does not interoperate, because each admits many
concrete instantiations. This document supplies the missing pin. It is deliberately narrow:
it profiles the *existing* Semaphore v4 / zk-kit stack rather than proposing new
cryptography, because the goal is a specification two teams can implement to, not a research
contribution.

The profile also discharges an obligation a responsible cryptographer owes the reader: to
state, prominently and early, where the chosen parameters fall short of a 128-bit classical
target and of any post-quantum target. See [Security and Privacy
Considerations](#security-and-privacy-considerations).

# Specification

## 1. Proving system and curve (profiles 11/PROOF-GATEWAY)

- Implementations MUST use **Groth16** [Groth16] as the proving system.
- The pairing-friendly curve MUST be **BN254** (also called alt-bn128 / BN128), the curve
  for which the EVM provides the pairing and scalar-multiplication precompiles [EIP-196]
  [EIP-197]. This choice is made for on-chain verification economics, not for security
  margin; see the security considerations.
- All field elements — identity commitments, Merkle roots, nullifiers, and public signals —
  are elements of the BN254 scalar field F_r, with
  `r = 21888242871839275222246405745257275088548364400416034343698204186575808495617`.
- The Groth16 verifying key MUST originate from a multi-party trusted-setup ceremony with a
  published transcript (Powers-of-Tau Phase 1 followed by a circuit-specific Phase 2). An
  implementation MUST record which ceremony its verifying key derives from. Security rests
  on the assumption that at least one ceremony participant destroyed their toxic waste.

## 2. ZK-friendly hash (profiles 09/CREDENTIAL-TREE-REGISTRY, 11)

- The hash MUST be **Poseidon** over F_r [Poseidon], in the instantiation used by
  iden3/circomlib and mirrored by `poseidon-solidity`, with:
  - S-box exponent α = 5 (permitted because gcd(5, r − 1) = 1 for BN254);
  - full rounds R_F = 8;
  - partial rounds R_P and width t taken from the reference parameter tables for each arity
    (for the binary tree node hash, arity 2, width t = 3);
  - round constants and MDS matrix generated by the reference Grain-LFSR procedure.
- Implementations MUST NOT hand-tune Poseidon parameters. Parameter selection MUST track
  the published cryptanalysis (see [Poseidon-GB]); the successor design [Poseidon2] is the
  RECOMMENDED migration target when performance requires it, adopted as a whole rather than
  by partial modification.

## 3. Holder identity and nullifier (profiles 09, 10, 11)

- A holder identity MUST follow Semaphore v4: an EdDSA key pair over the **Baby Jubjub**
  curve [EIP-2494], with the secret scalar derived from the private key per the Semaphore /
  circomlibjs convention.
- The identity commitment inserted into a credential tree MUST be
  `Poseidon(publicKey.x, publicKey.y)`.
- The nullifier MUST be `Poseidon(scope, secretScalar)`, deterministic per
  `(secret, scope)` and unlinkable to the holder outside the circuit.

## 4. Merkle accumulator (profiles 09)

- The accumulator MUST be the zk-kit **LeanIMT**: a binary incremental Merkle tree whose
  internal node is `Poseidon(left, right)`, in which a node with a single child takes that
  child's value unchanged (the LeanIMT optimisation), and whose leaves are identity
  commitments as defined in §3.
- Tree depth MUST be in the closed range [1, 32]; 11/PROOF-GATEWAY enforces this bound.

## 5. Public signals and domain separation (profiles 11)

- The Groth16 public signals MUST be, in this order:
  `[ merkleTreeRoot, nullifier, hash(message), hash(scope) ]`.
- `hash(x)` MUST be `keccak256(abi.encodePacked(uint256 x)) >> 8`, i.e. keccak256 over the
  32-byte big-endian encoding of `x`, right-shifted by 8 bits. The 8-bit shift guarantees
  the result is less than `r` (field-safe) and is the Semaphore v4 convention. See the
  security considerations for the collision-resistance implication of the truncation.
- `message` MUST carry the recipient binding as `uint256(uint160(recipientAddress))` where a
  proof is bound to a caller (e.g. 15/GATED-AIRDROP); other uses MUST document their
  `message` semantics.

## 6. Deterministic identifier encodings (profiles 04/SCHEMA-REGISTRY, 07)

- `schemaId` MUST be `keccak256(abi.encode(string uri, bytes32 contentHash))` using the
  canonical Ethereum ABI encoding of the two-element tuple, namely, concatenated as
  32-byte words:
  1. offset to `uri` data = `0x40`;
  2. `contentHash` (32 bytes);
  3. `uri` byte-length (32 bytes, big-endian);
  4. `uri` UTF-8 bytes, right-padded with zeros to a multiple of 32 bytes.
- A conformance test vector MUST accompany any independent implementation; see
  [Implementation Notes](#implementation-notes). A future major version MAY replace ABI
  encoding with an explicitly domain-separated construction, which would change all
  `schemaId` values and therefore requires a version bump.

## 7. Status list sizing (profiles 08/STATUS-LIST-REGISTRY)

- To preserve herd privacy, an issuer's status list SHOULD contain at least **131072**
  entries (the W3C minimum), and an implementation offering privacy guarantees on the basis
  of list size MUST reject configurations below this floor. Index allocation within a list
  SHOULD be uniformly random rather than sequential.

# Invariants

- Two implementations that conform to §§1–6 produce proofs, commitments, roots, nullifiers,
  and identifiers that each other accepts bit-for-bit.
- Any deviation in curve, hash instantiation, signal order, or encoding is a
  non-interoperable fork and MUST be published under a distinct profile version.

# Security and Privacy Considerations

## Curve security is below 128 bits — the headline caveat

BN254 was long cited at ~128-bit security, but improved tower-number-field-sieve analysis
lowered the estimate to roughly **100 bits** [BD17]. This is the single most important fact
in this profile. BN254 is mandated here for one reason only — it is the curve the EVM
prices cheaply via precompiles — and not because its margin is comfortable. Consequently:

- Implementations MUST NOT present the ZK path as offering 128-bit security.
- Deployments protecting long-lived or high-value credentials SHOULD treat BN254 as a
  medium-term choice and plan for migration to a higher-security pairing-friendly curve
  (e.g. BLS12-381) if and when the EVM prices it, or to an alternative verification path.
- The profile is versioned precisely so a curve migration is an explicit, reviewable event.

## No post-quantum security

Groth16 over BN254 relies on the hardness of discrete logarithms in pairing groups and is
**not** post-quantum secure; a cryptographically relevant quantum computer would break both
soundness (via forged proofs) and any long-term unlinkability that depends on the curve.
Poseidon and the Merkle structure are not the weak point. A post-quantum migration would
replace the proving system (e.g. with a hash-based STARK or a lattice-based SNARK) and is
out of scope here, but implementers MUST record this as a known end-of-life condition rather
than discover it later.

## Hash truncation in public signals

The `>> 8` truncation in §5 reduces `hash(message)` and `hash(scope)` to 248 bits, giving
~124-bit collision resistance. This is adequate for binding a message and a scope into a
proof, but implementations MUST NOT repurpose this construction where full 256-bit collision
resistance is required.

## Trusted-setup subversion

Per §1, a fully compromised Groth16 ceremony permits forged proofs. The multi-party
ceremony reduces this to "at least one honest participant"; the verifying key's provenance
MUST be auditable. This is a property of the deployment, not of this profile, but the
profile requires it be recorded.

## ZK-friendly hash cryptanalysis

Poseidon and its relatives are younger than SHA-2 and under active algebraic cryptanalysis
[Poseidon-GB]. The mitigation is to use only reference parameters (§2), to track the
literature, and to migrate wholesale to [Poseidon2] rather than patching parameters ad hoc.

# Interoperability

Conforming to this profile is what makes "Semaphore v4 tooling works unchanged" a true
statement: the curve, hash, identity, accumulator, and signal encoding are exactly those of
the deployed Semaphore v4 / zk-kit stack. An implementation that wishes to interoperate with
existing Semaphore wallets and provers MUST NOT deviate from §§1–5.

# Implementation Notes

- Independent implementations SHOULD ship conformance test vectors for: a Poseidon(2) node
  hash; an identity commitment from a known key pair; a nullifier from a known
  `(secret, scope)`; a `schemaId` from a known `(uri, contentHash)`; and a full Semaphore v4
  proof that a reference verifier accepts.
- The reference implementation pins `@semaphore-protocol/contracts` 4.14.3,
  `@zk-kit/lean-imt.sol` 2.0.1, and `poseidon-solidity` 0.0.5; these versions fix the
  concrete parameters profiled above and SHOULD be cited as the canonical instantiation
  until superseded.

# IANA Considerations

This document requests no IANA actions. It defines cryptographic parameters, not a value
namespace; see 00/REGISTRIES for the registries.

# Normative References

- [RFC2119] Bradner, S., "Key words for use in RFCs to Indicate Requirement Levels", BCP 14, RFC 2119, March 1997 — https://www.rfc-editor.org/rfc/rfc2119
- [RFC8174] Leiba, B., "Ambiguity of Uppercase vs Lowercase in RFC 2119 Key Words", BCP 14, RFC 8174, May 2017 — https://www.rfc-editor.org/rfc/rfc8174
- [Groth16] Groth, J., "On the Size of Pairing-Based Non-interactive Arguments", EUROCRYPT 2016 / IACR ePrint 2016/260 — https://eprint.iacr.org/2016/260
- [Poseidon] Grassi, L., Khovratovich, D., Rechberger, C., Roy, A., Schofnegger, M., "Poseidon: A New Hash Function for Zero-Knowledge Proof Systems", USENIX Security 2021 — https://www.usenix.org/conference/usenixsecurity21/presentation/grassi
- [EIP-196] Reitwiessner, C., "Precompiled contracts for addition and scalar multiplication on the elliptic curve alt_bn128" — https://eips.ethereum.org/EIPS/eip-196
- [EIP-197] Reitwiessner, C., "Precompiled contracts for optimal ate pairing check on the elliptic curve alt_bn128" — https://eips.ethereum.org/EIPS/eip-197
- [EIP-2494] Belles, M., Baylina, J., "Baby Jubjub Elliptic Curve" — https://eips.ethereum.org/EIPS/eip-2494

# Informative References

- [BD17] Barbulescu, R., Duquesne, S., "Updating key size estimations for pairings", IACR ePrint 2017/334 — https://eprint.iacr.org/2017/334
- [Poseidon2] Grassi, L., Khovratovich, D., Schofnegger, M., "Poseidon2: A Faster Version of the Poseidon Hash Function", IACR ePrint 2023/323 — https://eprint.iacr.org/2023/323
- [Poseidon-GB] Grassi, L., Koschatko, K., Rechberger, C., "Poseidon and Neptune: Gröbner Basis Cryptanalysis Exploiting Subspace Trails", IACR ePrint 2025/954 — https://eprint.iacr.org/2025/954
