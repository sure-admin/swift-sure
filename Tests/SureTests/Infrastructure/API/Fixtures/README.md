# Sure API contract fixtures

These fixtures represent the Sure API contract pinned at revision
`5594f8bc94c8e659838cac70d826bbcaeaa3bae2` in
`Docs/SureContractBaseline.md`.

Primary sources:

- [Generated OpenAPI document](https://github.com/we-promise/sure/blob/5594f8bc94c8e659838cac70d826bbcaeaa3bae2/docs/api/openapi.yaml)
- [Accounts response template](https://github.com/we-promise/sure/blob/5594f8bc94c8e659838cac70d826bbcaeaa3bae2/app/views/api/v1/accounts/_account.json.jbuilder)
- [Transactions response template](https://github.com/we-promise/sure/blob/5594f8bc94c8e659838cac70d826bbcaeaa3bae2/app/views/api/v1/transactions/_transaction.json.jbuilder)
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
- `error-unauthorized.json`, `error-preview-disabled.json`,
  `error-insufficient-scope.json`, `error-validation.json`: representative
  shared 401, preview-gated 403, scope 403, and 422 response bodies.
- `error-malformed.json`: valid JSON whose required error fields have invalid
  wire types.
