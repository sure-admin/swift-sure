# Sure contract baseline

## Supported upstream revision

During the developer and TestFlight phase, this client targets Sure `main` at:

- Commit: `5594f8bc94c8e659838cac70d826bbcaeaa3bae2`
- Upstream commit time: 2026-08-28 06:57:50 UTC
- Commit subject: `fix(holdings): an outbound transfer must not clear a cost basis (#3237)`

Permalinks for the contract sources used by this baseline:

- [OpenAPI](https://github.com/we-promise/sure/blob/5594f8bc94c8e659838cac70d826bbcaeaa3bae2/docs/api/openapi.yaml)
- [Client architecture](https://github.com/we-promise/sure/blob/5594f8bc94c8e659838cac70d826bbcaeaa3bae2/docs/clients.md)
- [Transaction API](https://github.com/we-promise/sure/blob/5594f8bc94c8e659838cac70d826bbcaeaa3bae2/docs/api/transactions.md)
- [Chat API](https://github.com/we-promise/sure/blob/5594f8bc94c8e659838cac70d826bbcaeaa3bae2/docs/api/chats.md)
- [AI architecture](https://github.com/we-promise/sure/blob/5594f8bc94c8e659838cac70d826bbcaeaa3bae2/docs/hosting/ai.md)

This is a deliberate compatibility pin, not a claim that Sure has a versioned
API. Backward compatibility with older self-hosted revisions is not required
yet. The app should nevertheless tolerate additive optional response fields.

## Current client policy

- Sure remains the system of record for financial data and calculations.
- Financial features are read-only. Authentication/session and APNs
  subscription lifecycle operations may write infrastructure state.
- Keep endpoint clients independent of credential storage and mutable UI state.
  They receive one immutable request context from the active session.
- Prefer documented typed endpoints. In particular, migrate insight loading to
  the documented `/api/v1/insights` operation during the typed API work instead
  of prompting chat to return tool JSON.
- Handle collection pagination explicitly when the endpoint supports it.
- Treat preview-feature 403 responses separately from invalid credentials.
- Keep wire DTOs, financial domain types, and SwiftUI presentation types
  separate.
- Require HTTPS for configured Sure servers. Debug builds may use plain HTTP
  only for loopback development hosts such as `localhost` and `127.0.0.1`.

## Pinned compatibility extensions

The pinned transaction response template emits `amount_cents` and
`signed_amount_cents` as integer minor-unit fields. They are not yet listed in
the generated OpenAPI `Transaction` schema. The typed client relies on these
fields for lossless signed money mapping and covers them with fixtures tied to
this revision. Do not assume that behavior for older Sure revisions.

The pinned chat show operation paginates messages in ascending order. Its Pagy
9 integration reports a legacy `per_page` value that does not match the
effective page size, so the client follows the returned `page` and
`total_pages` fields rather than recalculating the last page from `per_page`.

Budget typing remains deliberately deferred. The documented
`/api/v1/budget_categories` collection omits `actual_spending`, while the
existing budget UI requires that value. Preserving the screen with documented
operations would require category collection pagination followed by detail
hydration. Until that product/performance choice is made, budget loading stays
inside `LegacyBudgetAPIClient`; no other feature may depend on that legacy
transport or parsing behavior.

## Transaction product behavior

The first production transaction surface remains read-only:

- Account selection shows transactions belonging to that account from the
  rolling last 31 days.
- Overview Recent activity opens transactions across accounts from the rolling
  last 7 days.
- Foundational work should not redesign existing screens. Only the navigation,
  loading, empty, and error states required by these flows may change visually.

Date windows must be calculated through an injected calendar/clock so boundary
behavior is deterministic and testable. The typed transaction mapping must
retain the account identifier needed for account filtering.

## Authentication baseline

Passkey sign-in follows Sure's documented public-client OAuth flow: dynamic
client registration, Authorization Code with PKCE, a validated loopback
callback, code exchange, and best-effort revocation. OAuth refresh uses
`POST /oauth/token` with the cached client ID and rotated refresh token. Refresh
is single-flight, retries the rejected request at most once, and never applies
to API-key sessions.

The selected authorization kind, canonical server URL, and credential material
are one atomic device-Keychain record. A host-bound API-key backup may sync
through iCloud Keychain, but it does not override an active device session.
Legacy credentials that were stored separately from the server URL migrate
unverified and are never sent until the user explicitly confirms the host and
the app verifies or replaces them. OAuth tokens and API keys are redacted from
errors and diagnostics.

This client does not use Sure's separate mobile email/password device-token
flow. Adopting that workflow requires a distinct product decision and contract
review rather than being inferred from the browser/Passkey OAuth flow.

## Known migration gaps

Remaining gaps after the typed API foundation are:

- Budget loading still uses permissive `JSONSerialization`, recursive key
  lookup, the legacy nested category route, and fallback identifiers.
- Typed account and transaction records preserve integer minor units and
  currency, but existing SwiftUI presentation models still receive an explicit
  temporary `Double` conversion bridge.
- The Overview net-worth summary still combines presentation balances locally;
  it must move to Sure's authoritative balance-sheet result before it is treated
  as correct for mixed-currency families.

These gaps are migration inventory, not supported alternate contracts.

## Updating the pin

Adopt a newer Sure `main` revision deliberately:

1. Record the new full commit SHA and timestamp here.
2. Review relevant OpenAPI, client, transaction, chat, authentication, insight,
   and preview-feature changes between the two pins.
3. Update sanitized response fixtures and their provenance notes.
4. Update typed DTOs, endpoints, and compatibility policy together.
5. Run contract tests plus iOS, macOS, and Watch builds before committing.

Do not silently move this pin as part of unrelated feature work.
