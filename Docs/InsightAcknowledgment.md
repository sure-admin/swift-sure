# Insight acknowledgment rollout

The Apple client now calls `PATCH /api/v1/insights/{uuid}/acknowledge` through the
existing authenticated, subscription-gated transport. It requires `204 No Content`
before removing that row. There is no offline write fallback or queued credential-
independent mutation. Failure leaves the row available for retry.

The backend implementation is committed on `acknowledge-insights-api` in the
isolated checkout `/tmp/sure-insight-api-20261106`:

- Base upstream revision: `7367a14b31a48cbd22062d84eec4235f770d611f`.
- Backend change: `69266fe68`.
- Portable commit: [insight-acknowledgment.patch](BackendPatches/insight-acknowledgment.patch).

Apply that commit in the Sure backend with `git am` using the patch path. It has
not been pushed, merged, or deployed. This repository retains the patch so the
backend work remains reviewable and available after the temporary checkout is gone.
Deploy the backend before releasing the client behavior. Older servers reject the
write; the app reports the failure and retains the insight.

The API supports OAuth bearer and API-key authentication, requires `read_write`
scope and preview-feature access, and rejects guests. Family tenancy and shared-
account visibility match the insight feed. The action marks active insights read
and then acknowledged (stored status `dismissed`), preserving an existing read
stamp. Repeated requests preserve timestamps; expired insights stay expired.
Generators can resurface materially changed observations under existing policy.

The client fences stale refreshes after acknowledgment, updates cached payloads
atomically while retaining their original freshness, and publishes the remaining
feed to Watch. Logout and connection changes discard late UI updates.

Validation includes offline API, finance-state, and scoped-cache regression tests
on iOS and macOS; production-view swipe tests use an isolated UI host. Backend
validation uses disposable PostgreSQL and Redis: 11 Minitest cases, 35 assertions;
changed-file Ruby lint passes. OpenAPI was regenerated through rswag (457
documentation examples, no failures). Full backend pre-PR checks have not been run.
