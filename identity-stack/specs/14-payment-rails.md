---
slug: 14
title: 14/PAYMENT-RAILS
name: Settlement (Payment Rails)
status: draft
category: Standards Track
layer: Accountability & Economics
tags: settlement, micropayments, economics, issuer-funding, freeloader-problem
source: src/PaymentRails.sol
requires: 01/DID-REGISTRY
---

# Settlement (Payment Rails) Specification

# Change Process

This document specifies one component of the identity-stack proof of concept, derived from
`src/PaymentRails.sol`. That implementation and its test suite are normative where this
prose is ambiguous.

# Language

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD
NOT", "RECOMMENDED", "MAY", and "OPTIONAL" are to be interpreted as described in
[RFC 2119](https://www.ietf.org/rfc/rfc2119.txt).

# Abstract

The Payment Rails are the funding model for issuance. Issuers post a **per-verification
fee**; verifiers **pre-fund** a balance and **settle** per verification against an opaque
reference. Balances belong to the identifier, not the key, so a rotated or recovered issuer
keeps its earnings. No credential data touches the chain — only the payment and an opaque
reference. This is the missing settlement layer in roughly sixty lines.

# Motivation

Credential ecosystems fail economically before they fail technically: issuers bear the
cost of issuance and revocation infrastructure while verifiers capture the value of every
check. Industry analysis names this the **freeloader problem** — open standards mean anyone
can verify without compensating anyone. A settlement layer is the corrective:
per-verification payment, cheap enough (per the micropayment-economics literature) that
tiny transactions clear without a billing relationship, invoicing, or foreign exchange.

The design keeps settlement **machine-to-machine**, never user-facing, because the classic
reason micropayments failed on the web was the mental transaction cost of asking a human to
approve each one.

# Specification

## System Requirements

An implementation MUST provide:

- Issuer-controlled fee setting.
- Permissionless deposit crediting any identifier's balance.
- Owner-controlled withdrawal resolving control through 01/DID-REGISTRY.
- A settlement operation that moves a capped fee from verifier to issuer and emits a
  receipt.

## Data Structures

```text
balanceOf: mapping(address => uint256)   // wei held per identity
feeOf:     mapping(address => uint256)    // issuer => fee per verification (0 == not set)
```

## Interface

| Function | Access | Effect |
|---|---|---|
| `setFee(address issuer, uint256 fee)` | issuer owner | Post the per-verification price. |
| `deposit(address account)` payable | anyone | Credit any identifier's balance (funding another is harmless). |
| `withdraw(address account, uint256 amount)` | account's DID owner | Withdraw to the caller. |
| `settle(address verifier, address issuer, bytes32 ref, uint256 maxFee)` | verifier owner | Move `feeOf[issuer]` from verifier to issuer; emit a receipt. |

**Errors.** `InsufficientBalance`, `TransferFailed`, `FeeTooHigh` (fee exceeds the
verifier's stated `maxFee`), `NoFeeSet` (settlement attempted against an issuer with no
posted fee). **Events.** `Deposited`, `Withdrawn`, `FeeSet`, `VerificationSettled(verifier,
issuer, fee, ref)`.

## Protocol Flow

```mermaid
sequenceDiagram
  participant I as Issuer
  participant R as Payment Rails
  participant V as Verifier
  I->>R: setFee(fee)
  V->>R: deposit() pre-funds a balance
  Note over V: performs a verification off-chain
  V->>R: settle(issuer, ref, maxFee)
  Note over R: fee moves verifier to issuer; receipt emitted
  I->>R: withdraw()
```

1. An issuer calls `setFee(issuer, fee)`.
2. A verifier calls `deposit{value: ...}(verifier)` to pre-fund.
3. After a verification, the verifier calls `settle(verifier, issuer, ref, maxFee)`, where
   `ref` is an opaque hash (a policy id, a session commitment) and never credential data.
4. Both parties `withdraw` at will.

# Invariants

- **Balances belong to the identifier.** `withdraw` and `settle` resolve control through
  `DIDRegistry.identityOwner`, so rotated or recovered identities keep their funds.
- **Capped settlement.** `maxFee` caps every settlement, so an issuer cannot front-run a
  verifier's `settle` with a fee hike.
- **Fee required.** `settle` reverts when the issuer has posted no fee, so receipts cannot
  be forged as a zero-value audit trail naming arbitrary addresses.
- **No reentrancy surface.** State updates precede the single external call (`withdraw`),
  and settlement performs no external call.
- **Reference-only receipts.** `VerificationSettled` events are permanent and reference an
  opaque `ref` — never PII.

## Honest limitation

Settlement is **claimed by the verifier, not proven**: nothing compels a verifier to
`settle` for a verification it performed off-chain. Production designs close this loop by
making something the verifier needs conditional on payment — a wallet releasing a
presentation only on observing the settlement event, or the gateway pulling the fee. That
coupling is deliberately omitted here to keep the payment primitive legible, and each
candidate has a cost: the wallet-side approach burdens the holder; the gateway-side
approach couples two otherwise-independent components.

# Security and Privacy Considerations

## Threat model

- **Unenforced settlement (above).** Until coupling closes the loop, the rails measure
  honest participants and price signals, not compliance; procurement MUST NOT assume
  otherwise.
- **Metadata in the money.** Payment flows are public: who verifies against which issuer,
  when, at what volume. Timing correlation against verification events can narrow
  individuals; batch or delay settlement where volumes are small.
- **Fee manipulation.** Addressed by capped settlement (`maxFee`).
- **Receipt-forgery pressure.** Addressed by the `NoFeeSet` requirement, keeping the event
  log meaningful when receipts feed compliance reporting.

## Privacy

No credential data or subject identifier is ever involved in settlement; receipts carry
only an opaque `ref`.

# Interoperability

The rails are ETH-denominated in this PoC; ERC-20 support and fee-splitting
(issuer / trust-root / protocol) are the natural production extensions. Policy references
(13/POLICY-REGISTRY) SHOULD be carried in `ref` so a payment proves which policy governed
the verification.

# Implementation Notes and Production Path

- **Treat the rails as economics, not audit** until settlement is coupled to verification —
  and say so in any reporting built on them.
- **Batch settlement on a schedule** where verification volumes are low enough for timing
  correlation to matter.
- **Model issuer pricing on infrastructure cost recovery**, not profit, if the ecosystem is
  meant to be public infrastructure — the freeloader analysis cuts both ways.
- **Future work:** ERC-20 support, fee splitting, holder-side rewards (paying subjects for
  data use), streaming for subscription-style relationships.

# References

- Blockchain-based micropayment systems: economic impact, IEEE/ACM 2019 — https://www.researchgate.net/publication/334584292_Blockchain-based_micropayment_systems_economic_impact
- A Deeper Look at Credential Monetization and Ecosystem Payments (industry analysis) — https://www.dock.io/post/a-deeper-look-at-credential-monetization-and-ecosystem-payments
- Micropayments and the Future of the Web, Harvard Berkman Center — https://cyber.harvard.edu/fallsem98/final_papers/Worden.html
- RFC 2119 — https://www.ietf.org/rfc/rfc2119.txt

# Glossary

- **Fee.** The per-verification price an issuer posts.
- **Settlement.** Moving a capped fee from a verifier's balance to an issuer's, with a
  receipt.
- **Reference (`ref`).** An opaque hash tying a settlement to a verification without
  disclosing it.
