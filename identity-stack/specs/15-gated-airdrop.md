# GatedAirdrop (composability demo)

**Onchain value case.** This is the payoff slide: ~40 lines of application code buy sybil-resistance ("one claim per *person*", not per address), privacy (the contract never learns who claimed, only that each claimant was unique and credentialed), and policy (only credentials from issuers accredited by a chosen authority) — entirely by composing the stack. No allowlist ops, no offchain verifier service, no KYC vendor integration. That an application can inherit a full identity trust framework through three contract calls is Ethereum's distinctive argument in identity.

**How it works.** `claim(proof)` enforces, in order:

1. `proof.scope == campaignScope` — nullifier namespace = this campaign; the same person's actions in other scopes remain unlinkable.
2. `proof.message == uint160(msg.sender)` — the ZK proof cryptographically commits to the recipient; a mempool thief can't redirect it.
3. `TrustRegistry.isAccredited(authority, issuer, ROLE_ISSUER, schema)` — live policy check; de-accrediting the issuer stops claims *immediately*, mid-campaign.
4. `ProofGateway.validate(treeId, proof)` — real Groth16 verification + root recency (revocation) + nullifier consumption (one per person).

## Invariants (tested with real proofs)

- Same person, two proofs, two different wallets → second claim reverts (`NullifierAlreadyUsed`).
- Different person, same wallet pattern → succeeds.
- Stolen proof presented by another address → reverts (`ProofNotBoundToCaller`).
- Issuer de-accredited by the authority → claims stop (`IssuerNotAccredited`).

## Production path

Swap the claim counter for an ERC-20 mint; per-epoch scopes for recurring distributions; multiple accepted issuers via `checkChain` for federated trust.
