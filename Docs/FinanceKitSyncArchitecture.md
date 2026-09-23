# FinanceKit device publisher architecture

## Decision

FinanceKit is an on-device publisher into Sure, not a conventional provider that
Sure can poll. Sure's `Provider::FinancekitAdapter` should own canonical account
and transaction import behavior after an upload is accepted. A separate device
publisher boundary owns Wallet permission, source collection, Apple history
tokens, background delivery, bounded uploads, receipts, and device lifecycle.

This design incorporates the review of
[Sure PR 3529](https://github.com/we-promise/sure/pull/3529) and the requirements
in [Sure issue 3485](https://github.com/we-promise/sure/issues/3485). PR 3529's
family scoping, whole-payload validation, exact money/sign rules, explicit
mapping, identity-only import, pending-to-booked handling, tombstones, and
conservative disconnect behavior should remain. Its foreground-only transport,
decorative history metadata, enrollment-scoped source identity, and absence of
replacement, conflict, and background-delivery workflows should not become the
shipping contract.

The Apple client does not call PR 3529's draft sync endpoint. The current
implementation stops at an injected publisher transport until a revised,
generated OpenAPI contract is merged and pinned in `SureContractBaseline.md`.
It never falls back to generic account or transaction mutation APIs.

## Product boundaries

Local Wallet access and remote upload are separate decisions:

- FinanceKit authorization continues to power the free on-device Wallet preview
  without a Sure login, trial, or subscription.
- Upload requires a verified Sure connection, active backend entitlement,
  supported publisher capability, an explicit set of mapped accounts, and a
  separate consent screen. Consent must explain that selected Wallet account,
  balance, merchant, and transaction data becomes visible to the user's Sure
  family and may reach enrichment destinations configured on that Sure instance.
- A Sure logout disables background delivery, removes the scoped publisher
  credential and protected outbox. Authorized local Wallet accounts remain
  accessible independently of the Sure session. It does not claim to delete records already
  accepted by Sure.
- Entitlement loss disables delivery and the final HTTP gate. It preserves the
  publisher configuration and unacknowledged outbox so verified access can
  resume without changing source identity.
- Wallet revocation stops collection. Missing accounts, a narrower authorization
  window, or an incomplete snapshot never implies deletion from Sure.

No financial record, account identifier, merchant, server URL, credential, or
free-form error is sent to PostHog or written to diagnostics.

## Publisher and lineage model

The server creates a durable account lineage for every explicit create/link
decision. A device binding contains both the FinanceKit-local account UUID and
the server lineage UUID. Ledger identity must use the lineage plus the source
transaction identity and retain aliases/tombstones across ordinary disconnect
and re-enrollment; it must not depend on an enrollment or mapping row ID.

FinanceKit UUIDs are device-local. A second or replacement device is a new
publisher and may not assert continuity merely because names, amounts, or dates
look similar. Replacement must:

1. fence the previous publishing generation;
2. retain canonical lineage and prior source identities;
3. ask the user to confirm each account binding;
4. prove stable source IDs where available; and
5. create reviewable reconciliation work when account or transaction UUIDs
   change.

Only one active publisher may write a canonical lineage initially. Conflicts
remain visible through a typed API and UI until resolved; the client does not
silently claim manual, CSV, SimpleFIN, Plaid, or another device's entries.

## Stream protocol

Enrollment happens in the foreground with the normal gated Sure transport. The
server returns a same-origin upload URL, publisher ID, generation, stream ID,
record and byte limits, durable account bindings, and a revocable credential restricted to
that publisher and upload operation. The extension receives no API key, OAuth
access token, or refresh token. The upload URL is accepted only when it is HTTPS,
has the authenticated server's origin, stays below the configured base path, and
contains no user info, query, or fragment. Upload sessions reject redirects.

Credential renewal and repair acquire the same cross-process lock as the sync
engine before contacting the control plane. The lock remains held until the
returned credential and configuration are installed. Uploaders read credentials
only after acquiring that lock. Renewal preserves the checkpoint, sequence,
digest chain, and exact pending capture; only explicit repair resets a stream.
The foreground runner handles `publisher_unauthorized` with at most one renewal
and replay per pass. It never substitutes an OAuth token or creates a replacement
connection to recover a batch authentication failure.

Each immutable batch binds:

- protocol version, connection, publisher, generation, and stream;
- random batch and capture IDs;
- positive sequence and the exact previous payload digest;
- chunk index/count, snapshot or delta mode, capture time, and selected scope;
- typed account, balance, transaction, unavailable-account, and transaction
  tombstone events.

The extension posts the exact persisted bytes with a batch idempotency key and
SHA-256 digest. A receipt is valid only when it binds the same connection,
publisher, generation, stream, batch, sequence, and digest. `accepted` means the
server has durably stored the entire bounded batch and can finish without another
phone wake. `processing` and `applied` also acknowledge custody. A `failed`
receipt blocks the stream for explicit repair.

The server may receive retries or future sequences, but applies only a contiguous
stream. Reusing an identity or sequence with different bytes is a conflict.
Canonical source changes and the applied receipt commit atomically, followed by
recoverable normal Sure recalculation, rules, transfers, and enrichment work.
Health reports source observation, durable acceptance, canonical application,
and downstream completion separately.

## History tokens, chunks, and repair

FinanceKit account history is global; balance and transaction histories have an
opaque token per selected source account. Tokens remain encoded only in the App
Group state file and are never uploaded.

Collection writes all chunks and the candidate next checkpoint to the protected
outbox before network access. More than the server record limit is split into
ordered batches. The checkpoint advances only after every chunk receives a valid
durable receipt. An interrupted or ambiguous request retries the same bytes,
batch ID, sequence, and digest. This covers lost responses without duplicating
ledger transactions or creating sequence gaps.

An invalid Apple token marks the stream as requiring repair. The client does not
clear it and continue under the same stream. Foreground repair negotiates a new
stream/generation and a full snapshot. Snapshot completion describes coverage;
it never authorizes deletion. Explicit FinanceKit transaction deletions are the
only automatic retraction requests, and protected Sure entries remain conflicts
for review.

## Financial fidelity

The source event vocabulary keeps exact unsigned decimal magnitudes and a
separate credit/debit direction. The server normalizes Sure's sign once. Values
outside the published precision fail instead of rounding. Balance events preserve
every observed booked/available value, its source ID and observation time.
Transaction events preserve transacted and posted times, status, type, merchant,
original and display descriptions, merchant category code, foreign amount, and
exchange rate. The device performs no authoritative FX conversion.

Pending, authorized, booked, rejected, and memo states remain distinct.
Same-source-ID transitions update the same source identity. Different IDs are
not joined by amount/date heuristics. A pending replacement that cannot be proven
becomes server review work.

## Triggers

`FinanceKitSyncRunner` assembles the publishing stack and runs one pass. Two
triggers call it, and nothing else about the stack differs between them:

- the foreground trigger, `run(changedTypes:)`, which returns the outcome and
  throws so the settings surface can say what happened. It is called by **Sync
  now** and, debounced, when the scene becomes active. An empty `changedTypes`
  is the supported request to collect everything since the checkpoint.
- the background trigger, `runQuietly(changedTypes:)`, which swallows both, so
  the extension never logs credentials, payloads, account identifiers, or
  financial data.

The foreground trigger requires FinanceKit availability and the
`com.apple.developer.financekit` entitlement. This app supports iOS 18 or later;
eligible accounts and regions are determined by FinanceKit at runtime. The
foreground path does not require the separate background-delivery entitlement.
The background-delivery extension is
`@available(iOS 26.0, *)` and needs a FinanceKit background entitlement on a
second App ID, so it lands separately.

A capture the server has accepted but not yet imported is reported as
`FinanceKitSyncError.importPending`, distinct from `invalidReceipt`. The pending
capture and the FinanceKit checkpoint are deliberately retained, so the next
pass resumes the receipt poll rather than re-collecting. The foreground poll
stops after about thirty seconds, because a spinner is not the place to wait out
an import that resumes by itself.

## iOS background execution and storage

The iOS 26 background-delivery extension subscribes to account, balance, and
transaction changes hourly. The frequency is a system request, not a freshness
promise. Every wake also checks a verified StoreKit entitlement and sends through
`BackendAccessGate` plus `SubscriptionHTTPDataTransport`.

App and extension share only:

- a revocable publisher token in a device-only shared Keychain access group;
- configuration, Apple history tokens, and unacknowledged immutable batch bytes
  in an App Group file protected until first device unlock;
- a persistent App Group revocation marker written synchronously on logout and
  checked before credential access and every upload; and
- a cross-process file lock preventing the app and extension from advancing the
  same stream concurrently.

The file is excluded from backup and removed after acknowledgment or explicit
disconnect. Direct extension requests use an ephemeral URL session with no cache,
cookies, or redirects. A network failure leaves the checkpoint and exact outbox
unchanged for a later FinanceKit delivery. Returning from the extension callback
does not imply an upload succeeded.

## Activation gates

Before exposing enrollment UI or installing a production publisher
configuration:

1. merge the revised backend provider, inbox worker, conflict API, schemas,
   fixtures, and OpenAPI document, then update the pinned Sure revision;
2. implement the foreground capability, enrollment, mapping, replacement,
   repair, receipt, conflict-resolution, and disconnect clients against that
   exact contract;
3. verify scoped credential revocation and same-origin redirect rejection on a
   disposable HTTPS instance;
4. exercise more than 500 records, lost/repeated/reordered chunks, pending to
   booked, rejected/corrected/deleted records, stale balances, invalid tokens,
   authorization removal, entitlement expiry, disconnect/reconnect, device
   replacement, transfers, and concurrent family operations; and
5. test locked-device delivery, extension termination, offline recovery, and
   a no-app-open import on an eligible physical iPhone.

The current slice implements the App Group/Keychain boundary, StoreKit and
transport gates, exact outbox/receipt state machine, chunking, checkpoint
custody, history collector, source fidelity, lifecycle suspension, cleanup, and
the foreground trigger. It intentionally has no default publisher configuration
until those activation gates are met. The background-delivery extension target
is held on a separate branch until the Apple entitlement for
`am.sure.insights.financekit-background` is granted; the App Group, Keychain
access group, process lock, and file stores stay here so adding it back needs no
migration on already-installed devices.

## Experimental control plane

The iOS settings surface exposes enrollment, selected-account mapping, activation, an explicit **Sync now**, health, conflict repair, credential renewal, and remote disconnect only when `FINANCEKIT_ENABLED` is compiled and the background-processing subscription entitlement is current. It shows the server's accepted and imported times separately rather than one "last synced": accepting a capture and importing it are different facts, and collapsing them would claim a freshness Sure cannot vouch for. The client keeps the Apple history checkpoint and durable capture until the server reports the final batch `applied`. A replacement device never guesses that a new device-scoped FinanceKit transaction UUID is an existing ledger transaction; the server quarantines it as a `replacement_identity` conflict for explicit review.

This remains a device-only preview. There is no broad production rollout without the Apple background entitlement, Sure preview access, and explicit family-data consent.
