# Insight acknowledgment rollout

The Apple client now calls `PATCH /api/v1/insights/{uuid}/acknowledge` through the
existing authenticated, subscription-gated transport. It requires `204 No Content`
before removing that row. There is no offline write fallback or queued credential-
independent mutation. Failure leaves the row available for retry.

The backend implementation is committed on `acknowledge-insights-api` in the
isolated checkout `/tmp/sure-insight-api-20261106`:

- Base upstream revision: `7367a14b31a48cbd22062d84eec4235f770d611f`.
- Backend commits: `69266fe68` and review fixes `40bac49be`.
- Upstream PR: [we-promise/sure#4782](https://github.com/we-promise/sure/pull/4782).
- Portable commits: [insight-acknowledgment.patch](BackendPatches/insight-acknowledgment.patch).

The backend branch is published for review in the PR above; merging and
deployment remain pending. The portable patch can also be applied with `git am`.
This repository retains the patch independently of the temporary checkout.
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
validation uses disposable PostgreSQL and Redis: 12 Minitest cases, 41 assertions;
whole-repository Ruby, ERB, and Biome lint pass, and Brakeman reports no security
warnings. OpenAPI was regenerated through rswag (457 documentation examples, no
failures). The full local suite ran 14,830 tests with one unrelated failure: an
Ubuntu release-workflow script needs GNU `date` instead of macOS BSD `date`. All
10 release-workflow tests pass with GNU `date` in PATH. The corrected full rerun
was stopped after passing 10,000 tests without failures, with explicit approval
to publish a draft and use GitHub CI for the final full-suite result.

PR review fixes recheck shared-account visibility after acquiring the insight row
lock. The regression test returns 204 without the fix and 404 with it, preserving
the unread insight. All six insight documentation examples execute successfully;
the generated contract now declares OAuth `read_write` as an alternative to API
keys and places the UUID format inside the path parameter schema. Ruby lint and
the API consistency verifier pass. The initial PR revision passed GitHub's full
unit and system test jobs; the review revision uses CI for the full-suite result.
