# Overview spending comparison

## Integration status

The native card is placed immediately after Insights in Overview. Exact PWA
parity requires an upstream read-only API for the server's spending series.
Neither the pinned OpenAPI contract nor upstream `main` inspected on September
11, 2026 exposes this data. No endpoint or runtime fallback has been invented.
The existing contract pin remains unchanged. The Sure source uses
`UnavailableSpendingComparisonClient`, so its totals remain unavailable.
Authorized local Wallet accounts can independently populate the card through
`WalletSpendingComparisonClient`; this source is labeled explicitly and never
merged with Sure records. The chart is implemented and
can receive validated data through the injected `SpendingComparisonClient`.

`SpendingComparison` is a domain input, not a proposed wire schema. It requires
unfurled cumulative daily values (including zero-spend days), a server-local
as-of date, and a currency. It validates completeness, date ordering, and
nonnegative cumulative amounts before exposing header totals and chart points.
Decimal values are preserved through financial calculations and formatting;
conversion to Double is confined to chart coordinates and axis tick labels.

Sources inspected:

- [Original widget PR](https://github.com/we-promise/sure/pull/3404)
- [Current dashboard calculations](https://github.com/we-promise/sure/blob/main/app/controllers/pages_controller.rb)
- [Daily expense calculation](https://github.com/we-promise/sure/blob/main/app/models/income_statement/daily_expense_totals.rb)
- [Public API schema](https://github.com/we-promise/sure/blob/main/docs/api/openapi.yaml)

The PWA uses reporting-specific transaction/account exclusions, special handling
for investment contributions and loan payments, and daily exchange rates into
the family currency. The native transaction collection does not expose enough
information to reproduce these totals. Summing its expense records would be a
different financial presentation, not a substitute for the PWA calculation.

## Behavior to preserve

- Native month picker containing the current month and preceding 11 months.
- Current month is initially selected, including on the first three days.
- Green cumulative selected-month curve, ending today for the current month;
  gray complete previous-month curve, with a marker on the green endpoint.
- Explicit selected/previous month labels, formatted currency totals, and a
  signed delta. Lower spending is green; higher spending is red. Labels convey
  the comparison independently of color.
- For an in-progress month, compare totals through the same day in the previous
  month, clamped to that month's length. Historical months compare full totals.
  This matches the supplied screenshot and current upstream behavior, which
  differs from the original PR's full-previous-month header comparison.
- The selected month owns the horizontal axis. Current upstream folds extra
  days of a longer previous month into the last visible point, retaining the
  actual endpoint date for its tooltip. Do not use that folded point to derive
  the same-day header total.
- Include spending-free days so flat stretches remain flat. Provide daily
  inspection and accessible descriptions containing dates and exact totals.
- Distinct loading, empty, unavailable, and failure states. Never turn a failed
  request or an unsupported server into a zero-spending chart.

## Required upstream data

Expose the existing server calculation through a documented authenticated
read-only operation. The route and wire schema must be agreed upstream before
adding a client endpoint. It needs to supply:

- Requested/resolved month, server-local cutoff date, family currency, and
  current and previous date ranges.
- Complete daily series for both periods, with ISO dates and lossless decimal
  monetary amounts. Avoid the PWA chart's binary floating-point serialization.
- Selected total, comparison total, and comparison cutoff (or sufficient
  unfurled daily data to derive those presentation values without losing the
  distinction between the comparison cutoff and the full previous curve).
- Documented authorization scopes, month validation, empty responses, and errors.

Once available, update the contract pin and fixtures together and replace the
unavailable service at `AppDefinition` with a typed API adapter. Use the existing
transport for authorization and error handling. Do not add the path to the client
before upstream documents it. Month loading already remains independent of
Overview's income/spending month selection, and the store discards stale
responses after selection changes or session invalidation. Spending series are
not persisted in the existing Overview snapshot.

The focused domain and state tests cover current and historical months, January/year changes,
February/leap years, longer previous months, zero-spend days, empty periods,
currency precision, comparison deltas, failures, cancellation, and session
changes. Build and test on iOS and macOS, then inspect month selection, daily
values, Dynamic Type, and VoiceOver in the running interface.

Preparation validation: all 13 focused Swift Testing tests passed on iOS 27
Simulator and macOS 27, and both app targets built successfully. Native chart
renders were inspected at narrow and wide widths. Bitrig reported a successful
build and a running simulator, but its inspection tool returned that the
simulator does not support state, so touch and VoiceOver interaction remain
unverified. Live server parity and wire contract tests require the upstream API.

## Local Wallet source

When Wallet access has been explicitly enabled in Accounts, the card prefers
that source, including with no Sure connection. Overview refreshes Wallet access
on appearance, foregrounding, and manual refresh. Revocation, logout, account
changes, and reconnect invalidate displayed and in-flight spending snapshots.

`WalletSpendingAccessProviding` exposes authorized account IDs and known balance
currencies without coupling Overview to the Accounts view model. The injected
transaction provider obtains a complete local FinanceKit snapshot. The domain
builder filters by authorized account, inclusive date window, booked status,
debit direction, and non-transfer type, then aggregates integer minor units into
Decimal cumulative totals. Credits and refunds are not deducted, and the card's
information popover states that policy. No local records leave the device.

If currencies differ, the card displays an explicit unsupported comparison state
instead of inventing FX rates. A known balance currency permits an empty period
to display zero. With neither spending nor a known balance currency, it explains
that currency data is unavailable. Accounts without balances remain usable when
their transactions provide a currency.

Offline tests exercise source routing without Sure credentials, revocation,
query windows and account scope, debit/transfer/status filtering, duplicates,
empty and unknown-currency states, mixed currencies, and Decimal precision.
FinanceKit access itself requires an eligible physical iPhone; the simulator
cannot supply real Wallet accounts.

Wallet-source validation: the focused domain, service, state, and connection
suites passed on iOS Simulator and macOS. The final overlapping-refresh state
suite was rerun and passed on both platforms. An unsigned physical-iPhone build
also passed, compiling the FinanceKit implementation excluded by simulator
builds. Real Wallet data and permission interactions were not tested on a device.
