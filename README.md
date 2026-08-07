# Identity on Ethereum

What belongs onchain in digital identity — a proof of concept, a written
argument, and an explainer for institutional evaluators.

| Path | What it is |
|---|---|
| [`identity-stack/`](identity-stack/) | 16 contracts across four layers, a spec per component, and a test suite with real Groth16 proofs. Start at its [README](identity-stack/README.md). |
| [`POST.md`](POST.md) | The narrative argument: which identity state must be global, live and neutral, and which must never be onchain. |
| [`site/index.html`](site/index.html) | A self-contained interactive explainer for governments and institutions. Open it directly in a browser; no build step. |


## Running it

```bash
cd identity-stack && ./setup.sh
```

Installs Foundry if missing, installs dependencies, generates Groth16 proof
fixtures, and runs the suite. Currently **74 tests passing**. Without fixtures
the ZK suites skip cleanly and everything else still runs.

## State of the work

The stack is a proof of concept and is **unaudited**. Each spec carries a
"Production path" section naming what a real deployment would use instead —
in several cases an existing deployed contract (ERC-1056's registry, EAS,
Semaphore itself) rather than the minimal version here.

Reviewed against the Ethereum Foundation's
[CROPS mandate](https://ethereum.org/foundation/mandate/) — censorship
resistance, open source, privacy, security. Findings from that review are
fixed and captured in the specs.

### Decisions worth knowing before changing things

- **Nullifiers are namespaced per calling contract** in `ProofGateway`. This is
  load-bearing, not defensive styling: `validate` is permissionless, so a
  gateway-wide namespace would let anyone copy a pending proof from the
  mempool, front-run the consumer, and burn the nullifier — permanently
  excluding an honest holder, since nullifiers are deterministic per
  (secret, scope). Regression test:
  `test_DirectGatewayValidateCannotBurnClaim`.
- **`RecoveryModule` never fully deletes an attempt.** `approved` is keyed by
  round, so resetting the round counter would let a guardian's stale approval
  resurface as an `AlreadyApproved` lockout. Clearing `newOwner` alone is
  correct — do not "tidy" it into `delete attempts[identity]`.
- **The delegation nonce is monotonic.** `revokeAll` orphans grants rather than
  erasing them, so any code path that decrements or re-sets a nonce silently
  resurrects every revoked grant.
- **Three privacy claims are deliberately narrow.** Onchain status checks are
  publicly visible in calldata; the ZK anonymity set is only ever the tree; and
  commitments appear in issuance and revocation events, linking a credential's
  lifecycle. All three are inherent, documented rather than "fixed".

### Build note

`@zk-kit/lean-imt.sol` is installed under the npm alias
`@zk-kit/lean-imt-sol`. Foundry, through at least 1.7.1, mis-resolves a
remapping target whose directory name ends in `.sol`, dropping the trailing
separator. Import paths in `src/` are unchanged.

## Open

- No top-level CI. The suite runs locally via `setup.sh`.
- Proof-of-personhood issuance is out of scope — this stack consumes personhood
  credentials, it does not mint them.
- Remaining open questions are listed at the end of [`POST.md`](POST.md) and in
  the limitations section of the explainer.

## License

MIT — see [identity-stack/LICENSE](identity-stack/LICENSE).
