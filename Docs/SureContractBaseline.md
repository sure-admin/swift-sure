# Sure contract baseline

## Supported upstream revision

This client targets the merged Sure `main` revision below, including the cash-flow
Sankey contract from [backend PR #3558](https://github.com/we-promise/sure/pull/3558).

- Commit: `e526fac7e0d8a5591d1fc0bc1d275b08fe917e97`
- Upstream commit time: 2026-09-15 04:40:31 UTC
- Commit subject: `Add cash_flow Sankey API and instrumented dashboard preview (#3558)`

Permalinks for the contract sources used by this baseline:

- [OpenAPI](https://github.com/we-promise/sure/blob/e526fac7e0d8a5591d1fc0bc1d275b08fe917e97/docs/api/openapi.yaml)
- [Client architecture](https://github.com/we-promise/sure/blob/e526fac7e0d8a5591d1fc0bc1d275b08fe917e97/docs/clients.md)
- [Transaction API](https://github.com/we-promise/sure/blob/e526fac7e0d8a5591d1fc0bc1d275b08fe917e97/docs/api/transactions.md)
- [Balance-sheet controller](https://github.com/we-promise/sure/blob/e526fac7e0d8a5591d1fc0bc1d275b08fe917e97/app/controllers/api/v1/balance_sheet_controller.rb)
- [Chat API](https://github.com/we-promise/sure/blob/e526fac7e0d8a5591d1fc0bc1d275b08fe917e97/docs/api/chats.md)
- [AI architecture](https://github.com/we-promise/sure/blob/e526fac7e0d8a5591d1fc0bc1d275b08fe917e97/docs/hosting/ai.md)

This is a deliberate compatibility pin, not a claim that Sure has a versioned
API. Backward compatibility with older self-hosted revisions is not required
yet. The app should nevertheless tolerate additive optional response fields.

The pin adds opt-in Sankey graphs to `GET /api/v1/cash_flow?include=sankey`.
Monthly reporting, account eligibility, FX, refund netting, hierarchy, and flow
balancing remain server-owned. The client validates the graph, caches it with the
monthly summary, and computes only drawing geometry. Old cache records without
a graph remain readable, but a successful live response must contain the
requested graph. No local Wallet Sankey or connected aggregation fallback exists.
The native client sends only `month` and `include=sankey`; it never combines
`include` with `view`, which the merged API rejects. Public API authentication
remains gated API-key/OAuth. The dashboard's cookie-authenticated route is
`/dashboard/cash_flow` and is not used by the native client. The merged monthly
response and graph schemas are unchanged from the reviewed candidate.

## Current client policy

- Sure remains the system of record for financial data and calculations.
- Financial features are read-only. Authentication/session and APNs
  subscription lifecycle operations may write infrastructure state.
- Keep endpoint clients independent of credential storage and mutable UI state.
  They receive one immutable request context from the active session.
- Prefer documented typed endpoints. Insight loading uses
  `/api/v1/insights` instead of prompting chat to return tool JSON.
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

The documented `/api/v1/budget_categories` collection omits
`actual_spending`, while the existing budget UI requires that value. The typed
client therefore paginates budgets, deliberately selects the single current
budget, paginates its category summaries, and hydrates each summary through
`/api/v1/budget_categories/{id}`. Integer minor-unit fields from those detail
responses are the lossless source for category spending and limits.

Sure serializes `Money#amount` through Rails `BigDecimal`, which may use
exponent-form decimal strings. The client accepts that lossless representation
and validates it against Sure's pinned currency registry, including BTC, DOGE,
USDC, GBX, GGP, IMP, and JEP rather than relying on Apple's platform registry,
which omits those Sure-supported codes.

Authoritative balance-sheet totals may contain sub-minor-unit precision after
Sure applies exchange rates. Those totals remain `Decimal` through the domain
and are rounded only for display; native account, transaction, and budget values
continue to use the server's integer minor units.

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
flow. It does use the pinned mobile SSO handoff for the initial Google and Apple
providers: `google_oauth2` and `apple` respectively. The server redirects through
`sureapp://oauth/callback`; existing identities return a single-use code for
`POST /api/v1/auth/sso_exchange`, while unknown identities return a short-lived
linking code for the future onboarding flow. The provider route opens in the
system browser, matching Sure's upstream mobile client, and the app resumes the
pending authentication when iOS or macOS delivers that callback. Mobile refreshes use
`POST /api/v1/auth/refresh` with the stable per-install device identifier.

The pinned server does not publish enabled SSO providers. Until a discovery
operation is added, administrators must configure the two provider names above;
the client treats an unavailable provider as a safe, user-visible sign-in error.

## Financial presentation invariants

The typed read-only foundation has no remaining legacy financial parser or
binary floating-point presentation bridge:

- Accounts, transactions, balance-sheet values, and budget categories retain
  integer minor units and Sure currency codes through feature state and formatting.
- Overview net worth comes from the documented `/api/v1/balance_sheet`
  operation. Native account balances are never summed as a substitute.
- Period income and spending use the server's cash-flow result in family
  currency, including Sure's exchange-rate rules.

`Double` conversions are confined to Swift Charts geometry and axis ticks.
Account charts require one reporting currency; each spending comparison
uses one currency from its explicitly labeled source. Local Wallet spending is
calculated separately on-device and is never combined with Sure data. Monetary summaries remain lossless Decimal
values. The spending comparison uses the cash-flow API; see
[its integration status](SpendingComparison.md).

## Updating the pin

Adopt a newer Sure `main` revision deliberately:

1. Record the new full commit SHA and timestamp here.
2. Review relevant OpenAPI, client, transaction, chat, authentication, insight,
   and preview-feature changes between the two pins.
3. Update sanitized response fixtures and their provenance notes.
4. Update typed DTOs, endpoints, and compatibility policy together.
5. Run contract tests plus iOS, macOS, and Watch builds before committing.

Do not silently move this pin as part of unrelated feature work.
