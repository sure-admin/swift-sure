# Sure contract baseline

## Supported upstream revision

During the developer and TestFlight phase, this client targets the coordinated Sure backend revision below (merge its draft PR before deploying this client):

- Commit: `982dc0a42a83ffa476324a9ec3c9351b90a080b5`
- Upstream commit time: 2026-09-13 05:46:56 UTC
- Commit subject: `Expose authoritative native reporting and prove push-device continuity`

Permalinks for the contract sources used by this baseline:

- [OpenAPI](https://github.com/we-promise/sure/blob/982dc0a42a83ffa476324a9ec3c9351b90a080b5/docs/api/openapi.yaml)
- [Client architecture](https://github.com/we-promise/sure/blob/982dc0a42a83ffa476324a9ec3c9351b90a080b5/docs/clients.md)
- [Transaction API](https://github.com/we-promise/sure/blob/982dc0a42a83ffa476324a9ec3c9351b90a080b5/docs/api/transactions.md)
- [Balance-sheet controller](https://github.com/we-promise/sure/blob/982dc0a42a83ffa476324a9ec3c9351b90a080b5/app/controllers/api/v1/balance_sheet_controller.rb)
- [Chat API](https://github.com/we-promise/sure/blob/982dc0a42a83ffa476324a9ec3c9351b90a080b5/docs/api/chats.md)
- [AI architecture](https://github.com/we-promise/sure/blob/982dc0a42a83ffa476324a9ec3c9351b90a080b5/docs/hosting/ai.md)

This is a deliberate compatibility pin, not a claim that Sure has a versioned
API. Backward compatibility with older self-hosted revisions is not required
yet. The app should nevertheless tolerate additive optional response fields.

The pin includes `GET /api/v1/financial_summary` and optional installation-proof
push registration. [Financial summary contract](https://github.com/we-promise/sure/blob/982dc0a42a83ffa476324a9ec3c9351b90a080b5/docs/api/financial-summary.md).
Existing account, transaction, budget, balance-sheet, chat, and auth fixtures
remain additive-compatible; new summary fixtures and push-request tests cover
these operations. This pin is deliberate, not an older-server fallback.

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
- Period income and spending remain grouped by currency. The client does not
  invent exchange rates or label a mixed-currency total as one currency.

`Double` conversions are confined to Swift Charts geometry and axis ticks.
Account charts require one reporting currency; each spending comparison
uses one currency from its explicitly labeled source. Local Wallet spending is
calculated separately on-device and is never combined with Sure data. Monetary summaries remain lossless Decimal
values. The spending comparison has no live API adapter yet; see
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
