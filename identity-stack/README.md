# identity-stack

Minimal MVP PoC of the onchain use cases for digital identity on Ethereum.
Fifteen small contracts, four layers, real ZK proofs. Each component has a spec
in [`specs/`](specs/); the narrative is in [`../POST.md`](../POST.md).

## Layout

| Layer | Contracts |
|---|---|
| Identity | `DIDRegistry` (ERC-1056 minimal), `RecoveryModule`, `DelegationRegistry` |
| Credential | `SchemaRegistry`, `IssuerRegistry`, `TrustRegistry`, `AttestationRegistry` |
| Status & privacy | `StatusListRegistry`, `CredentialTreeRegistry` (LeanIMT), `NullifierRegistry`, `ProofGateway` (Semaphore v4 Groth16) |
| Verification & economics | `VerifierRegistry`, `PolicyRegistry`, `PaymentRails`, `GatedAirdrop` (demo) |

## Run it

```bash
./setup.sh
```

which does: install Foundry if missing → `npm install` (Solidity deps +
Semaphore JS) → `forge install forge-std` → generate real Groth16 proof
fixtures (`npm run fixtures`; first run downloads Semaphore's snark artifacts)
→ `forge test`.

Without fixtures, the ZK test suites skip cleanly and everything else still
runs — `forge test` passes either way.

## Dependencies (pinned)

`@semaphore-protocol/contracts@4.14.3`, `@zk-kit/lean-imt.sol@2.0.1`,
`poseidon-solidity@0.0.5`, forge-std. Proof fixtures generated with
`@semaphore-protocol/core` v4.

`@zk-kit/lean-imt.sol` is installed under the npm alias `@zk-kit/lean-imt-sol`
(same package, same pinned version). Foundry — through at least 1.7.1 — drops
the trailing separator when a remapping target is a directory whose name ends
in `.sol`, so the real install path fails to resolve. The alias sidesteps it;
import paths in `src/` are unchanged.

## Status

PoC. Unaudited. Deliberately minimal — see each spec's "Production path".

## License

MIT — see [LICENSE](LICENSE).
