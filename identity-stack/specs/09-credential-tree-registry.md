# CredentialTreeRegistry

**Onchain value case.** The privacy-preserving half of issuance and revocation. The chain never sees a credential, a subject, or a plaintext attribute — only Poseidon commitments in a Merkle tree. Yet any contract can verify, trustlessly, that someone holds a currently-valid credential from a specific issuer. This is the primitive that reconciles "public verifiability" with "no PII onchain".

Two limits on that claim, stated up front because they are easy to deploy straight past — see [Privacy limits](#privacy-limits) below: the anonymity set is only ever the tree, and commitments are public in event data.

**How it works.** Each issuer owns Lean Incremental Merkle Trees (zk-kit LeanIMT — the Semaphore v4 accumulator). Issue = insert the holder's *identity commitment* (Poseidon of a secret that never leaves the holder's device). Revoke = zero the leaf (`_remove`), changing the root so revoked credentials immediately fail membership proofs against fresh roots. A root-history window (`rootDuration`) keeps recent roots provable so an honest holder's in-flight proof isn't broken by an unrelated issuance in the same block — the exact tradeoff dial between UX and revocation latency.

## Interface

| Function | Access | Effect |
|---|---|---|
| `createTree(issuer, rootDuration) → treeId` | issuer owner | New tree |
| `issue(treeId, commitment)` / `issueMany` | tree issuer | Insert commitment(s), record new root |
| `revoke(treeId, commitment, siblings[])` | tree issuer | Zero the leaf; new root recorded |
| `currentRoot(treeId)` / `isValidRoot(treeId, root)` | view | Root checks (current, or historical within window) |
| `hasCredential(treeId, commitment)` | view | Transparent membership check (for issuer ops, not holders) |

## Invariants

- Only the tree's issuer DID mutates it; control follows key rotation.
- Every root the tree has ever had is timestamped; `isValidRoot` accepts the current root always, historical roots only within `rootDuration`.
- A revoked commitment cannot re-prove against any root newer than its revocation (LeanIMT update is verified onchain against supplied siblings — a wrong path reverts `WrongSiblingNodes`).

## Privacy limits

**The anonymity set is the tree.** A membership proof hides *which* member you are, among the members there are. In a tree of three, it identifies you to one-in-three. Tree size is therefore not an operational detail but the privacy parameter, and the danger is that the natural way to organise trees destroys it: a tree per cohort ("Q1 2026 KYC applicants, Germany") makes tree membership itself the sensitive attribute, and proving membership discloses exactly the thing the ZK path was chosen to protect. Prefer few large trees over many small ones; never create a tree whose *composition* is the disclosure you are trying to avoid.

**Commitments are public, so lifecycles are linkable.** `CredentialIssued` and `CredentialRevoked` both carry the commitment in the clear — unavoidably, since offchain indexers must be able to rebuild the tree to generate proofs. The chain therefore holds a permanent record that *this commitment* was issued at block X and revoked at block Y. The commitment is not itself identifying, but it is a stable pseudonym: anyone who learns a holder's commitment through any side channel (a careless wallet, an issuer's logs, a subpoena) can read that holder's entire credential history retroactively, forever. Holders who need unlinkability across credentials need a fresh identity secret per credential, which the Semaphore identity model supports and which the PoC does not demonstrate.

**Revocation timing is a side channel.** Even without knowing a commitment, a small tree with infrequent writes leaks: if one credential is revoked in a quiet week, and one holder stops transacting that week, the two are correlatable.

## Design notes

- **Valid-credentials tree, not revoked-credentials tree**: membership proofs are LeanIMT's native strength; non-membership proofs are not.
- Revocation latency = `rootDuration`. Issuers choose per tree: an event-ticket tree might tolerate 24h; a KYC tree might want minutes.
- Gas: insert is O(log n) Poseidon hashes (~250k gas at depth 20 — Poseidon in the EVM is the cost center; an EVM Poseidon precompile would change this materially).

## Production path

Semaphore v4 itself (groups = trees, battle-tested); batched revocations; L2 trees with L1 root checkpointing; ERC-7812-style unified ZK registry.
