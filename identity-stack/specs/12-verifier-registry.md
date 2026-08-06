# VerifierRegistry

**Onchain value case.** "Verified verifiers" flips identity's usual asymmetry: today the holder is endlessly vetted while the verifier — the party actually *collecting* data — is anonymous and unaccountable. A public verifier directory, combined with TrustRegistry accreditation and a published policy, lets wallets enforce a rule today's ecosystems can't express: *don't present credentials to verifiers nobody vouches for.* Over-asking becomes visible, attributable, and cheap to punish (revoke the accreditation once, every wallet reacts).

**How it works.** Structurally the mirror of IssuerRegistry: self-registration of `(identity, metadataURI)` with an active flag. Trust comes from `TrustRegistry.isAccredited(authority, verifier, ROLE_VERIFIER, schema)`; what the verifier asks for comes from PolicyRegistry. The wallet-side check before releasing a presentation is: registered ∧ accredited by a root I accept ∧ active policy I accept.

## Interface

| Function | Access | Effect |
|---|---|---|
| `register(identity, metadataURI)` | identity owner | Self-register |
| `setActive(identity, bool)` | identity owner | Pause |
| `isActive(identity) → bool` | view | registered ∧ ¬paused |

## Invariants

- Permissionless registration; endorsement is TrustRegistry's, disclosure policy is PolicyRegistry's. Three separable concerns, three contracts.
- Control follows the DID.

## Production path

Fold registration/policy/accreditation views into a single wallet-facing "shouldIPresentTo(verifier, schema, myRoots[]) → bool" helper; alignment with eIDAS relying-party registration requirements, which this maps to almost one-to-one.
