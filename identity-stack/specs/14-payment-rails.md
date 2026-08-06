# PaymentRails

**Onchain value case.** Credential ecosystems die economically before they die technically: issuers bear the cost of issuance and revocation infrastructure while verifiers capture the value. Ethereum collapses the missing settlement layer to a few storage writes: verifiers prepay, each verification settles the issuer's posted fee instantly, globally, without invoicing, FX, or bilateral contracts. Fee flows are public — the first credential ecosystem where the *economics* are as auditable as the credentials.

**How it works.** Issuers post a per-verification fee. Verifiers `deposit()` a balance. On each verification the verifier calls `settle(issuer, ref)` — `ref` is an opaque hash (policy id, session commitment); no credential data touches the chain. Balance moves verifier→issuer; both withdraw at will.

## Interface

| Function | Access | Effect |
|---|---|---|
| `setFee(issuer, fee)` | issuer owner | Post per-verification price |
| `deposit(account)` payable | anyone | Prepay any identity's balance |
| `settle(verifier, issuer, ref, maxFee)` | verifier owner | Move fee, emit receipt event |
| `withdraw(account, amount)` | account's DID owner | Withdraw to caller |

## Invariants

- Balances belong to the *identity*, not the key: `withdraw`/`settle` resolve control through DIDRegistry, so rotated or recovered identities keep their funds.
- `maxFee` caps every settlement — an issuer can't front-run a verifier's `settle` with a fee hike.
- Settlement requires a posted fee (`NoFeeSet`). Otherwise a verifier could emit zero-value receipts naming any address it chose, and `VerificationSettled` — the thing that makes ecosystem economics auditable — would be forgeable noise.
- `settle` reverts if the verifier's balance can't cover the fee; state updates precede the only external call (withdraw), so no reentrancy surface.
- Receipts (`VerificationSettled` events) are permanent and reference-only — no PII.

## Honest limitation

Settlement is *claimed* by the verifier, not proven: nothing forces a verifier to call `settle` for an offchain verification it performed. Production designs close this loop by making something the verifier needs conditional on payment — e.g. the holder's wallet releases the presentation only after seeing the settlement event, or ProofGateway.validate itself pulls the fee. That coupling is deliberately left out of the MVP to keep the payment primitive legible.

## Production path

ERC-20 support, fee splitting (issuer/trust-root/protocol), holder-side rewards (paying *subjects* for data use), streaming for subscription-style verification relationships.
