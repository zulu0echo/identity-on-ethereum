# PolicyRegistry

**Onchain value case.** Data-minimization rules (GDPR, eIDAS 2.0) are enforced today by audits after the harm. An immutable, versioned, public record of *exactly what a verifier asks for and promises about retention* changes the enforcement model: wallets refuse non-compliant policies automatically (ex-ante, not ex-post), and any policy change is a permanent timestamped event a regulator or journalist can diff. You cannot quietly start over-collecting.

**How it works.** The policy document (accepted schemas, trusted roots, retention promise, purpose) lives offchain; `publish(verifier, uri, contentHash)` appends an immutable version and makes it active. `setActive` rolls between published versions but can never edit one. Wallets pin the `contentHash` they consented to; if the active hash changes, consent is re-prompted.

## Interface

| Function | Access | Effect |
|---|---|---|
| `publish(verifier, uri, contentHash) → policyId` | verifier owner | Append version, auto-activate |
| `setActive(verifier, policyId)` | verifier owner | Switch among published versions |
| `activePolicy(verifier) → (policyId, Policy)` | view | What the verifier currently claims to do |
| `policyCount` / `policyAt` | view | Full history |

## Invariants

- Versions are append-only and immutable; the full history of a verifier's asks is permanently public.
- Exactly zero or one active policy per verifier at any time.

## Production path

Machine-readable policy format (a presentation-definition dialect + retention fields) so wallets can *evaluate*, not just pin, policies; policy commitments referenced in PaymentRails receipts so payments prove which policy governed each verification.
