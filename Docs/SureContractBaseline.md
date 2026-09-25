# Sure contract baseline

## Supported upstream revision

During the developer and TestFlight phase, this client targets the Sure `main` revision below, which includes merged [backend PR #3545](https://github.com/we-promise/sure/pull/3545):

- Commit: `d4d97b8feee229c64331cc9daa3cf75c7b8a1b6b`
- Upstream commit time: 2026-09-14 04:57:17 UTC
- Commit subject: `Expose cash flow reporting and secure push-device continuity (#3545)`

Permalinks for the contract sources used by this baseline:

- [OpenAPI](https://github.com/we-promise/sure/blob/d4d97b8feee229c64331cc9daa3cf75c7b8a1b6b/docs/api/openapi.yaml)
- [Client architecture](https://github.com/we-promise/sure/blob/d4d97b8feee229c64331cc9daa3cf75c7b8a1b6b/docs/clients.md)
- [Transaction API](https://github.com/we-promise/sure/blob/d4d97b8feee229c64331cc9daa3cf75c7b8a1b6b/docs/api/transactions.md)
- [Balance-sheet controller](https://github.com/we-promise/sure/blob/d4d97b8feee229c64331cc9daa3cf75c7b8a1b6b/app/controllers/api/v1/balance_sheet_controller.rb)
- [Chat API](https://github.com/we-promise/sure/blob/d4d97b8feee229c64331cc9daa3cf75c7b8a1b6b/docs/api/chats.md)
- [AI architecture](https://github.com/we-promise/sure/blob/d4d97b8feee229c64331cc9daa3cf75c7b8a1b6b/docs/hosting/ai.md)

This is a deliberate compatibility pin, not a claim that Sure has a versioned
API. Backward compatibility with older self-hosted revisions is not required
yet. The app should nevertheless tolerate additive optional response fields.

The pin includes `GET /api/v1/cash_flow` and optional installation-proof
push registration. [Cash flow contract](https://github.com/we-promise/sure/blob/d4d97b8feee229c64331cc9daa3cf75c7b8a1b6b/docs/api/openapi.yaml).
Existing account, transaction, budget, balance-sheet, chat, and auth fixtures
remain additive-compatible; new summary fixtures and push-request tests cover
these operations. The merge preserves all existing GET contracts, shared schemas,
and push-registration contracts from the previously tested revision; its other
OpenAPI changes affect trade mutations, which this client does not use. This pin
is deliberate, not an older-server fallback.

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

The FinanceKit control plane and batch protocol use a scoped supplemental pin:
[PR #3633's merge, `355648ce5d67b5b68fff5723ca5298467047e72e`](https://github.com/we-promise/sure/commit/355648ce5d67b5b68fff5723ca5298467047e72e).
The general API baseline above remains unchanged. The FinanceKit fixtures
(`Tests/SureTests/Infrastructure/API/Fixtures/financekit-*.json`) represent
protocol 2. Activation returns a plain `publisher_credential` string beside the
configuration; receipts distinguish acceptance from import and bind the full
publisher/stream/batch identity.

Publisher authentication and renewal were checked against this revision's
[OpenAPI](https://github.com/we-promise/sure/blob/355648ce5d67b5b68fff5723ca5298467047e72e/docs/api/openapi.yaml),
[batch controller](https://github.com/we-promise/sure/blob/355648ce5d67b5b68fff5723ca5298467047e72e/app/controllers/api/v1/financekit/batches_controller.rb),
and [publisher model](https://github.com/we-promise/sure/blob/355648ce5d67b5b68fff5723ca5298467047e72e/app/models/financekit_item.rb):

- Batch upload and receipt lookup use `Authorization: Bearer <publisher_credential>`,
  independently of user OAuth/API-key authorization.
- Invalid publisher credentials return HTTP 401 with
  `{"error":"publisher_unauthorized"}` (the corresponding sanitized fixture).
- Credential renewal immediately replaces the server's credential digest without
  changing generation, stream, sequence, or predecessor digest. Repair changes
  generation and stream and resets sequence continuity.
- The client locks rotation and credential installation against uploads, preserves
  pending batches on renewal, and retries a rejected foreground pass only once
  after renewing the publisher credential. Other failures do not trigger rotation.

These are offline contract checks, not proof of any particular deployment's
configuration. Adoption of the broader merged server revision still requires the
normal baseline review.

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

Batch validation diagnostics also follow the pinned
[`Financekit::Payload` validator](https://github.com/we-promise/sure/blob/355648ce5d67b5b68fff5723ca5298467047e72e/app/models/financekit/payload.rb).
The `financekit-batch-invalid-payload.json` fixture represents its HTTP 422
`{"error":"invalid_payload"}` response. The publisher persists only a closed set
of known validation codes, fences automatic retries, and retains the original
outbox and checkpoint until explicit repair starts a new stream. Unknown response
text is neither persisted nor displayed. These diagnostics do not identify the
specific field when upstream returns the generic `invalid_payload` code.

The client can locally inspect the retained rejected batch for common event
violations, without retrying or modifying it. The synthetic
`financekit-booked-missing-posted-at.json` fixture demonstrates a booked record
whose optional FinanceKit posting date is absent: the current Swift mapping
omits `posted_at`, while the pinned validator requires it for `booked`. Diagnostics
identify an event index, field, and rule only. They also check text limits using
Unicode code points (Ruby string semantics), supported statuses, capture-relative
dates, and duplicate identities. This inspection is partial and does not replace
server validation; lack of a local finding is not a claim that the payload is valid.
Do not substitute transaction dates for missing posting dates, reclassify booked
records, or drop financial records to make this contract mismatch disappear.

Wallet consent is now a persisted client preference, with existing configured
publishers migrated from their already-recorded consent. Withdrawing consent stops
local delivery before remote disconnection. A failed disconnection retains a
revoked configuration for retry, and the off choice survives relaunch. The pinned
`DELETE /api/v1/financekit/connections/{id}` operation explicitly retains imported
history. Upstream `main` was also checked for this change and still exposes no
FinanceKit-specific transaction deletion option. The confirmation dialog therefore
explains that deletion is unavailable rather than deleting accounts, resetting a family, or guessing
at a transaction filter. Supporting that choice requires a documented server
operation scoped to Wallet-ingested records.


Wallet account presentation uses the pinned FinanceKit connection detail operation
(`GET /api/v1/financekit/connections/{id}`, every page). Its mapping `source_id`
and nullable `account_id` link on-device Wallet accounts to canonical Sure accounts;
account names and balances are never used as identity. Only a mapping to an account
actually present in the validated account collection suppresses a local card.
Source identity is retained in the existing authenticated account cache, survives
stopping uploads, and is cleared with that cache on logout. The client labels these
canonical cards “Apple Wallet” and uses the Wallet icon; the generic account API
currently omits FinanceKit institution provenance. This is a client presentation
label, not a mutation of server institution data or the source's institution name.

Sure's pinned `Financekit::Mapping.balance` stores CreditCard debit balances as
positive debt and credit balances as negative overpayments. The upload keeps this
contract unchanged. `FinanceAccount.balance` retains the server value; account
cards render liabilities with their sign inverted exactly once in Decimal, so debt
appears negative and overpayments positive, matching the local Wallet convention.
Assets preserve their signed balance (including overdrafts). Older cached cards
infer liability presentation from their existing account kind until refreshed.
Net worth still comes exclusively from Sure's balance-sheet endpoint.
