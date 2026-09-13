# Sure API contract fixtures

These fixtures represent the Sure API contract pinned at revision
`5594f8bc94c8e659838cac70d826bbcaeaa3bae2` in
`Docs/SureContractBaseline.md`.

Primary sources:

- [Generated OpenAPI document](https://github.com/we-promise/sure/blob/5594f8bc94c8e659838cac70d826bbcaeaa3bae2/docs/api/openapi.yaml)
- [Accounts response template](https://github.com/we-promise/sure/blob/5594f8bc94c8e659838cac70d826bbcaeaa3bae2/app/views/api/v1/accounts/_account.json.jbuilder)
- [Transactions response template](https://github.com/we-promise/sure/blob/5594f8bc94c8e659838cac70d826bbcaeaa3bae2/app/views/api/v1/transactions/_transaction.json.jbuilder)
- [Budget response template](https://github.com/we-promise/sure/blob/5594f8bc94c8e659838cac70d826bbcaeaa3bae2/app/views/api/v1/budgets/_budget.json.jbuilder)
- [Budget category response templates](https://github.com/we-promise/sure/tree/5594f8bc94c8e659838cac70d826bbcaeaa3bae2/app/views/api/v1/budget_categories)
- [Balance-sheet controller](https://github.com/we-promise/sure/blob/5594f8bc94c8e659838cac70d826bbcaeaa3bae2/app/controllers/api/v1/balance_sheet_controller.rb)
- [Insights controller](https://github.com/we-promise/sure/blob/5594f8bc94c8e659838cac70d826bbcaeaa3bae2/app/controllers/api/v1/insights_controller.rb)
- [Shared API error handling](https://github.com/we-promise/sure/blob/5594f8bc94c8e659838cac70d826bbcaeaa3bae2/app/controllers/api/v1/base_controller.rb)

All identifiers, names, institutions, merchants, amounts, and timestamps are
synthetic. No fixture contains credentials, authorization headers, personal
financial data, or response bodies captured from a live server.

The primary transaction success fixtures include `amount_cents` and
`signed_amount_cents`. The pinned response template emits these integer
minor-unit fields, although the generated OpenAPI `Transaction` schema does not
yet list them. A separate fixture verifies the deliberate `amount_cents`-only
fallback. Contract code should treat both fields as a pinned compatibility
extension rather than assume they exist on older Sure servers.

Fixture coverage:

- `accounts-page-1.json`, `accounts-page-2.json`: a complete two-page account
  collection, including signed liability values and a zero-decimal currency.
- `accounts-empty.json`: the empty collection envelope.
- `accounts-malformed.json`: an account missing its required server `id`.
- `balance-sheet-success.json`: the authoritative reporting currency, net
  worth, assets, and liabilities using the exponent-form decimal strings
  emitted by Rails for Sure `BigDecimal` money values.
- `balance-sheet-fx-precision.json`: a valid cross-currency total whose raw
  precision extends below the reporting currency's display unit.
- `balance-sheet-mismatched-currency.json`: a nested liability value whose
  currency contradicts the reporting currency.
- `transactions-page-1.json`, `transactions-page-2.json`: a complete two-page
  transaction collection with expense, income, nullable associations, and a
  zero-decimal currency.
- `transactions-empty.json`: the empty collection envelope.
- `transactions-malformed-date.json`: an otherwise valid transaction with a
  non-ISO date.
- `transactions-amount-cents-only.json`: expense and income normalization when
  only the pinned absolute minor-unit extension is present.
- `transactions-missing-cents.json`: a transaction that cannot be mapped
  losslessly because neither minor-unit extension is present.
- `transactions-inconsistent-sign.json`: a signed minor-unit value that
  contradicts the server classification and must be rejected.
- `budgets-page-1.json`, `budgets-page-2.json`: historical and current budgets
  across two pages, proving that the client selects the current budget only
  after consuming the complete collection.
- `budgets-empty.json`, `budgets-no-current.json`: families with no budgets and
  with no current budget.
- `budgets-multiple-current.json`: an invalid response with two current budgets.
- `budgets-malformed.json`: a current budget missing its required currency.
- `budget-categories-page-1.json`, `budget-categories-page-2.json`: paginated
  category summaries for the selected current budget.
- `budget-categories-empty.json`: a current budget with no category summaries.
- `budget-categories-malformed.json`: a summary missing its required server ID.
- `budget-category-groceries-detail.json`,
  `budget-category-housing-detail.json`: detail hydration containing exact
  actual-spending and display-budget minor units.
- `budget-category-malformed-detail.json`: detail missing the required exact
  `actual_spending_cents` value.
- `insights-success.json`, `insights-empty.json`: populated and empty insight
  collections.
- `insights-malformed.json`: an insight with an unsupported priority value.
- `chat-empty.json`, `chat-stale-reply.json`, `chat-message-submission.json`,
  `chat-message-failed.json`, `chat-with-reply.json`: typed chat creation,
  message submission, stale-response exclusion, failure, and polling responses.
- `chat-page-1.json`, `chat-page-2-stale.json`,
  `chat-page-2-new-reply.json`: a long chat whose newest response is available
  only on its last page.
- `push-subscription-success.json`: a typed APNs subscription response.
- Push deletion deliberately preserves a typed 404 so the notification
  lifecycle can treat an already-missing server subscription as successful,
  idempotent cleanup.
- `error-unauthorized.json`, `error-preview-disabled.json`,
  `error-insufficient-scope.json`, `error-validation.json`: representative
  shared 401, preview-gated 403, scope 403, and 422 response bodies.
- `error-malformed.json`: valid JSON whose required error fields have invalid
  wire types.

## Native reporting baseline

The client now targets Sure `982dc0a42a83ffa476324a9ec3c9351b90a080b5`. The
financial-summary success/empty/malformed fixtures use the new bounded monthly
contract: decimal strings, canonical IANA family time zone, server-local cutoff,
and complete unfurled daily curves. Existing fixtures continue to cover the
unchanged portions of the public contracts. Push registration also permits a
per-server installation proof, tested in the typed request contract.
