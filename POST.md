# What actually belongs onchain in digital identity

*A minimal, working stack of every onchain identity use case — 15 small contracts, real ZK proofs, all runnable.*

Most digital identity has no business being on a blockchain. Credentials, personal data, presentation flows — all of that lives offchain, on devices, between wallets and verifiers. Put PII onchain and you've built a privacy disaster with a permanence problem.

But strip identity systems down and you find a small set of things that *must* be global, live, and neutral — state that every participant needs the same view of, that no single party should control, and that has to keep working when companies fold, servers die, or governments change their minds. That's exactly the state Ethereum is good at. Everything else is better off elsewhere.

This post enumerates those onchain use cases — what each one is worth and how it works — and ships a proof of concept: a composable stack of 15 deliberately minimal contracts with specs and tests, including real Groth16 proofs on the privacy path. Nothing here is novel cryptography; the point is to map the whole surface in one place and show the pieces composing.

The stack holds itself to five constraints throughout: privacy (no PII onchain, ever), self-sovereignty (users hold keys and secrets, no custodian), credible neutrality (permissionless registries, no global root of trust), open source, and security (the trust-critical checks happen in consensus, not in a company).

## The test for "does this belong onchain?"

Each use case below passes the same test: the state is only useful if everyone sees the same version of it, it changes over time so snapshots go stale, and its availability must not depend on the party who wrote it. Registries of control, validity, trust, and uniqueness pass. Credential data fails — deliberately.

## Layer 1: who controls an identifier

**Key registry (DID registry).** Everything downstream needs one answer to "who controls this identifier right now?" — an answer that survives key rotation. The PoC's `DIDRegistry` is minimal ERC-1056: every address is a DID at zero cost, and the registry stores only deviations — rotated owners, expiring key delegates. One `identityOwner()` call, and because every other registry in the stack resolves control through it, rotating a key once rotates control of every registration everywhere. Losing a key stops meaning re-enrolling with every counterparty.

**Social recovery.** "What if I lose my key?" is where self-sovereign designs usually fall back to a custodian — reintroducing the trusted party they were meant to remove. Onchain guardian recovery keeps it non-custodial and, critically, *transparent*: `RecoveryModule` does n-of-m guardian approval plus a timelock, and because attempts are public events, the real owner sees a malicious recovery coming and cancels it. Programmable recovery policy, enforced by consensus rather than a support desk.

**Scoped delegation.** The near future of identity is agents acting for people: "my AI agent may present my KYC credential until Friday." That grant needs to be checkable by parties who trust neither the person nor the agent, and revocable everywhere at once. `DelegationRegistry` holds capability-scoped, expiring grants with an O(1) kill switch (`revokeAll`). Contrast bearer capabilities (signed JWTs): those stay valid until expiry wherever they've been copied. Onchain revocation propagates in one block.

## Layer 2: who says what about whom

**Schema registry.** Interoperability starts with issuer and verifier agreeing on a credential's shape — forever. `SchemaRegistry` is content-addressed and append-only: a schemaId means the same thing in year ten as at registration, which no web-hosted schema can promise.

**Issuer registry + issuer schemas.** Verifiers need to discover issuers and pin their identity over time; issuers need somewhere public to commit to what they issue. `IssuerRegistry` is permissionless self-registration plus schema declarations. Note what it deliberately doesn't do: registration asserts zero trustworthiness. Discovery and endorsement are separated on purpose —

**Trust registry (accreditation).** — because "why believe this issuer?" deserves its own primitive. Today that question is answered by closed, jurisdiction-bound trusted lists. `TrustRegistry` makes accreditation an open graph: any authority can vouch for `(subject, role, schema)`, every relying party picks which authorities it treats as roots, and `checkChain` walks eIDAS-style hierarchies in one view call. No global root of trust — that's the credible-neutrality constraint doing real work. And revoking an accreditation reaches every verifier on the network in one block, which no trusted-list distribution mechanism can match.

**Verified verifiers.** The same primitive, pointed the other way — and my favorite use case, because it fixes identity's oldest asymmetry: holders get endlessly vetted while verifiers, the parties actually collecting data, stay anonymous and unaccountable. With `VerifierRegistry` + accreditation, a wallet can enforce *"don't present credentials to verifiers nobody vouches for."* Over-asking becomes visible and attributable.

**Verifier policy registry.** `PolicyRegistry` completes that story: verifiers publish versioned, immutable policies (what they request, what they retain) as content hashes. Wallets pin the hash they consented to; any change is a permanent public diff. Data-minimization enforcement moves from after-the-fact audits to wallets refusing bad policies automatically.

**Direct onchain attestations.** When a claim has no PII and is public by nature — this contract passed an audit, this org holds a license — the simplest representation wins: the claim itself, in the clear, onchain. `AttestationRegistry` is a minimal EAS-shaped registry; `isValid(uid)` is the one-call gate any contract can compose on. (In production you'd just use EAS.)

## Layer 3: is it still valid — and can you prove it privately

Revocation is where offchain credential systems quietly leak trust. CRLs go stale; status endpoints go down; and phone-home checks let the issuer log where the credential gets used. Onchain status gives every verifier the same answer at the same block — and the issuer never learns who asked. The PoC ships both flavors:

**Status lists (transparent path).** `StatusListRegistry` ports the W3C Bitstring Status List onchain: one bit per credential, 256 per storage word, one SLOAD to check. Revocation bits are one-way by contract invariant; suspension lists can reinstate. Cheap and simple, but not private: the verifier learns which index it's checking, and if the check happens in a transaction rather than an `eth_call`, the index is in public calldata permanently — which credential was checked, when, by whom. The win over a phone-home CRL is specifically that the *issuer* stops learning where its credentials get used, not that nobody learns.

**Credential trees (private path).** `CredentialTreeRegistry` gives each issuer Merkle trees of credential *commitments* (zk-kit's LeanIMT, the Semaphore v4 accumulator). Issuance inserts a commitment; revocation zeroes the leaf. The chain never sees a credential or a subject — but any holder can prove membership in ZK: "I hold a currently-valid credential from this issuer," nothing more. A root-history window keeps in-flight proofs alive across unrelated issuances; its length is exactly your revocation latency, tunable per tree.

Two caveats that belong next to that claim rather than in a footnote, because a deployment can satisfy every invariant here and still not be private. The anonymity set is only ever the tree: a membership proof hides which member you are among the members that exist, so a three-person tree hides almost nothing, and organising trees per cohort ("Q1 applicants, Germany") makes tree membership itself the disclosure. And commitments appear in the clear in issuance and revocation events — they must, or nobody can rebuild the tree to prove against it — so each commitment is a permanent pseudonym linking a credential's issuance to its revocation. Neither is a flaw in the primitive; both are ways to hold it wrong.

**Nullifiers.** Anonymity without double-use protection is worthless. A nullifier is deterministic per (holder secret, context) but unlinkable to the holder; `NullifierRegistry` consumes each one exactly once per scope. This single mapping is what makes one-person-one-vote, sybil-resistant airdrops, and quadratic funding enforceable — with no biometrics and no coordinator. Different scopes yield unlinkable nullifiers, so acting in poll A doesn't link you to airdrop B.

**Proof gateway (verification with no verifier).** `ProofGateway` wraps the Semaphore v4 Groth16 verifier: root recency (that's revocation), pairing check, nullifier consumption — about 250k gas, no verification service anywhere. The proof's `message` field binds the claimant's address into the proof itself, so a stolen proof is useless to anyone else. The verifier can't profile you, censor you, or go down, because it's a pairing equation in consensus, not a company.

## Layer 4: the economics

**Payment rails.** Credential ecosystems tend to die economically before they die technically: issuers carry the infrastructure cost, verifiers capture the value. `PaymentRails` is the missing settlement layer in ~60 lines: issuers post a per-verification fee, verifiers prepay and `settle()` per verification with an opaque reference — no invoicing, no bilateral contracts, no credential data. One honest gap, flagged in the spec: settlement is claimed, not proven. Closing that loop (wallets releasing presentations only on observed payment, or the gateway pulling fees) is the interesting design problem.

## The payoff: composability

`GatedAirdrop` is the whole argument in ~40 lines of application code: one claim per *person* (not per address), only for holders of valid credentials from an issuer accredited by a chosen authority, with the claimant unknown to the contract. Its tests — running real proofs — show the same person blocked across two different wallets, a de-accredited issuer stopping claims mid-campaign instantly, and a stolen proof failing for any other sender.

No allowlist ops. No KYC vendor integration. No offchain verifier. An application inherits a complete identity trust framework through three contract calls. That composability — every new registry making every existing application more capable — is Ethereum's distinctive argument in identity, and no bilateral-integration architecture replicates it.

## What's in the PoC

| Layer | Contracts |
|---|---|
| Identity | DIDRegistry · RecoveryModule · DelegationRegistry |
| Credential | SchemaRegistry · IssuerRegistry · TrustRegistry · AttestationRegistry |
| Status & privacy | StatusListRegistry · CredentialTreeRegistry · NullifierRegistry · ProofGateway |
| Verification & economics | VerifierRegistry · PolicyRegistry · PaymentRails · GatedAirdrop |

Each contract has a spec (`specs/`) covering the value case, interface, invariants, and the path from PoC to production. `./setup.sh` installs the toolchain, generates real Semaphore proofs, and runs the full suite; without fixtures the ZK tests skip and everything else still passes. Dependencies are pinned: Semaphore contracts 4.14.3, zk-kit LeanIMT 2.0.1, poseidon-solidity 0.0.5.

W3C alignment throughout: identities resolve as did:ethr (ERC-1056), status lists mirror Bitstring Status List semantics, schemas point at VC data-model documents, and the proof shape is stock Semaphore v4, so existing prover tooling works unchanged.

## Open questions

Honest edges, worth discussing:

*Where do the registries live?* Everything here deploys to an L2 for cost, but trust registries and nullifiers want maximal neutrality and permanence — which argues L1, or L2 state with L1 checkpoints. Cross-domain nullifier consistency (one action per person *across* chains) is genuinely unsolved.

*Poseidon gas.* The LeanIMT path pays for Poseidon in the EVM. Issuance at depth 20 runs a few hundred thousand gas; fine on L2, heavy on L1. An EVM Poseidon precompile would change the economics of every ZK identity design at once.

*Root windows are a real tradeoff.* Short windows mean fast revocation and broken in-flight proofs; long windows the reverse. Per-tree tuning helps but the tension is fundamental.

*Anonymity sets are an operational problem, not a cryptographic one.* Every ZK identity design shares this and few say it plainly: the maths is only as private as the population you hide in, and the pressure to segment trees by issuer, cohort, jurisdiction, and date runs directly against it. Who is responsible for keeping trees large — the issuer with an incentive to segment, or the wallet that could refuse to prove against a tree below some size threshold? I think it's the wallet, which means tree size needs to be cheaply readable and wallets need a norm about it. Neither exists yet.

*Payment enforcement*, per above — the rails settle, but nothing yet compels settlement.

*What I left out:* proof-of-personhood itself (this stack consumes personhood credentials; it doesn't mint them) and cross-chain bridging of identity state, each a post of its own.

The repo is deliberately boring Solidity — the shortest honest implementation of each idea, so the ideas themselves are inspectable. If a use case is missing from the map, that's the feedback I most want.
