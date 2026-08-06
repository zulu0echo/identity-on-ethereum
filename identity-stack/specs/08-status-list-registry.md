# StatusListRegistry

**Onchain value case.** Revocation is where offchain credential systems leak trust: CRLs go stale, OCSP endpoints go down or log who's asking. An onchain bitmap gives every verifier the same revocation answer at the same block, with no phone-home to the issuer (the *holder-privacy* win: the issuer never learns where a credential was presented), at ~1 storage word per 256 credentials.

**How it works.** Onchain port of the W3C Bitstring Status List: the offchain VC carries `(issuer, listId, index)`; checking status is one SLOAD: `getStatus(issuer, listId, index)`. Lists have purposes with different write rules — `Revocation` bits are one-way (permanence is an invariant, not a promise), `Suspension` bits can be cleared (reinstatement).

## Interface

| Function | Access | Effect |
|---|---|---|
| `createList(issuer, listId, purpose, uri)` | issuer owner | Create a list (purpose fixed forever) |
| `setStatus(issuer, listId, index, status)` | issuer owner | Flip one credential's bit |
| `getStatus(issuer, listId, index) → bool` | view | One-SLOAD status check |

## Storage

`words[issuer][listId][index >> 8]` — 256 credential statuses per word; bit `index & 0xff`.

## Invariants

- Revocation-purpose bits can be set but never cleared.
- Anyone can read; only the issuer DID writes; the *history* of every flip is in events (auditable revocation, unlike a CRL file quietly replaced).

## Tradeoff vs CredentialTreeRegistry

Transparent and ~20k gas per revocation, but the check is not private. Two distinct leaks, and the second is the one that surprises people:

- The verifier learns *which* index — and therefore which credential — it is checking.
- If the check happens **onchain** (any composing contract must call `getStatus` in a transaction), the `(issuer, listId, index)` triple sits in public calldata forever. That is a permanent public record of which credential was checked, when, and by whom — strictly more exposure than the offchain CRL this replaces, which at least leaked only to the issuer. An `eth_call` from a verifier's own node leaks nothing; a contract call leaks to everyone.

So the holder-privacy win here is narrow and worth stating precisely: the *issuer* no longer learns where a credential was presented. Everyone else may learn more. Where the check itself is sensitive, use the ZK path. The two share the issuance story; a production credential would typically carry both a status-list entry and a tree commitment.

## Production path

Batch word writes, L2 deployment with L1 root checkpoints, alignment with W3C `BitstringStatusList` JSON-LD so the same VC statusListCredential field can point at a contract instead of an HTTPS URL.
