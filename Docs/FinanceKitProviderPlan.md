# FinanceKit device provider implementation plan

Status: proposed implementation; no runtime behavior changes in this commit.
Reviewed: 2026-09-09.

Backend prerequisite: [we-promise/sure#3485](https://github.com/we-promise/sure/issues/3485).
Native provider implementation is deferred until that issue's backend acceptance
criteria are met: merged implementation, deployed migrations/workers, published
contract and fixtures, and verified ingestion/recovery behavior. Then adopt the
implementing Sure revision before beginning the native work below.

Build a family-scoped `financekit` provider in Sure, with the iPhone acting as
its data collector. After the user explicitly enables server sync, the phone
collects authorized Wallet changes, durably queues them, and uploads them to
Sure without requiring the user to open the app. Sure owns account linking,
transaction reconciliation, balance calculations, and financial presentation.

The primary background trigger is Apple's **iOS 26 FinanceKit background
delivery extension**. A SwiftUI task, timer, or an ordinary FinanceKit monitoring
sequence in the main app does not satisfy this requirement. Delivery frequency
is controlled by iOS, and no design can guarantee an always-running service,
real-time updates, or a fixed hourly deadline. Initial setup and authorization
require foreground interaction. Normal subsequent collection and upload must
work without it. [Apple background delivery][apple-extension]

## 1. Baseline and decisions

Backend analysis targets the client's pinned Sure revision
`5594f8bc94c8e659838cac70d826bbcaeaa3bae2`, not an assumed current `main` or the
demo server. The pin stays unchanged until the server changes land and the
client adopts their actual revision with updated fixtures.

The installed iOS SDK is 26.5. Its FinanceKit Swift interface confirms that
`BackgroundDeliveryExtension`, `BackgroundDeliveryExtensionProviding`, and
`enableBackgroundDelivery(for:frequency:)` are available from iOS 26.0.
No SDK 27 API is needed. Preserve the app's iOS 18, macOS 15, and watchOS 11
minimums; give the iOS-only extension a minimum of iOS 26. Guard calls from the
host app. Older iOS versions retain foreground collection/sync with clearly
reduced background capability. Mac and Watch continue reading Sure data.
FinanceKit eligibility must be checked at runtime on each device; iPad or
regional availability must not be assumed from OS version alone.

Proposed product decisions for implementation:

- This request introduces a narrow financial-write exception: opt-in ingestion
  through the FinanceKit provider. Existing financial screens remain read-only.
- Enabling local Wallet access does **not** imply consent to upload. Ask for
  separate consent naming the canonical Sure server, selected accounts,
  available history, ongoing background uploads, and retention on the server.
- Start with one active publishing device per linked Sure account. Other
  devices can view it. Device replacement is an explicit handover.
- Upload accounts, balance observations, and transaction changes. Do not promise
  access to every Apple Pay purchase or arbitrary Wallet cards.
- Preserve booked and available balances separately; authoritative balance
  calculations use booked data when supplied. Missing booked data stays unknown
  or explicitly estimated, never silently substituted with available credit.
- Preserve source statuses. Booked transactions affect authoritative spending;
  pending/authorized records remain pending. Rejected/memo records do not become
  booked spending.
- Keep the current Accounts design. Add focused setup and sync status controls;
  do not redesign Overview or the other features.

## 2. What exists and what must change

| Boundary | Inspected behavior | Required change |
| --- | --- | --- |
| Apple client | `FinanceKitAppleCardConnector` queries accounts, balances, and transactions for local display | A separate incremental export adapter with complete source identity/status/date/balance information |
| Local history | Fetches transactions, then filters by account and UI date window | Export authorized history independently of the 7/31-day navigation windows; use change tokens |
| App composition | `AppDefinition` creates local and Sure history clients; `AppDelegate` handles notifications | Inject headless sync services and background transfer lifecycle handling |
| Persistence | App session is device Keychain state; financial snapshots are display caches | App Group transactional outbox and dedicated shared device upload credential |
| Sure providers | `Provider::Factory`, `AccountProvider`, provider item/account models | Add `FinancekitItem`, `FinancekitAccount`, and `Provider::FinancekitAdapter` |
| Sure ingestion | `Account::ProviderImportAdapter` supplies import identity, edit protection, and reconciliation | FinanceKit-specific processors plus strict batch intake and replay protection |
| Sure API | OpenAPI has read-only provider connection status and sync status; no FinanceKit intake | Publish versioned device enrollment, mapping, batch, receipt, and revocation contracts |
| Sync scheduling | `Family::Syncer` discovers syncable provider item associations | Process received data without pretending Rails can fetch the phone's Wallet |

The provider generator is a structural reference, not a complete solution:
its normal integration expects Rails to pull from an external API. This provider
receives data pushed by the device. It needs no global Apple bank credentials
and no publicly reachable endpoint on the phone. `Provider::Registry` currently
registers global market/LLM concepts; the relevant financial account registration
is `Provider::Factory`. [Provider generator][sure-generator],
[factory][sure-factory], [import adapter][sure-import], [OpenAPI][sure-openapi]

## 3. End-to-end architecture

```text
User authorizes Wallet + explicitly opts into selected Sure server
  -> authenticated enrollment and account mapping
  -> dedicated device credential + destination encryption key

Wallet changes
  -> FinanceKit BackgroundDeliveryExtension (iOS schedules execution)
  -> incremental collector
  -> transactional App Group outbox + local FinanceKit history tokens
  -> encrypted, signed file upload through background URLSession
  -> family/device-scoped Sure batch inbox + durable receipt
  -> ordered Rails processing job
  -> FinancekitAccount -> AccountProvider -> Sure Account / Entry / Transaction
  -> existing balance, rule, transfer, and enrichment workflows
  -> normal Sure read APIs on iPhone / iPad / Mac / Watch
```

Keep these distinct: source read checkpoint, upload accepted by Sure, and
financial import completed. A network completion or `202 Accepted` is not
“transactions synced.”

### Durable collection and upload

1. Read account changes first using `accountHistory(since:isMonitoring: false)`.
   Read balances and transactions per selected account using
   `accountBalanceHistory` and `transactionHistory`, also with monitoring off.
   Drain finite history batches within an injected execution budget.
2. Persist opaque Codable `HistoryToken`s locally: one account token, and
   balance/transaction tokens per account, partitioned by destination, device,
   enrollment generation, and selection generation. Never send Apple tokens
   to Rails or infer their internal contents.
3. In one local database transaction, persist each complete change batch and
   its next token. Advancing a token is safe only when its changes are durably
   recoverable from the outbox; it does not require waiting for the network.
   Crash before commit means reread. Crash afterward means replay the outbox.
4. Turn durable records into immutable, bounded upload files. Persist the batch
   UUID, digest, sequence, encryption key version, and file/task association.
   Recover crashes between file creation, database commit, and task scheduling
   by reconciling known files and `getAllTasks`, then replaying the same batch ID.
5. Keep the encrypted payload until Sure has durably accepted it. Keep receipt
   metadata until its import reaches a terminal state. The server owns retries
   after durable acceptance; the phone must not need another wake to apply it.
6. Persist retry deadlines and a bounded exponential backoff policy with jitter.
   Honor `Retry-After`; retry transport failures, timeouts, 429, and recoverable
   5xx. Reconcile ambiguous responses by batch ID. Pause on revoked credentials,
   unsupported protocol, mapping conflicts, or invalid records, with sanitized
   remediation. No unbounded loops or discarded malformed records.
7. Use a real cross-process transaction/lease mechanism (for example SQLite WAL
   with short writer transactions and recoverable leases). A Swift actor only
   serializes one process. Never hold a database lock while awaiting a network
   response. Prioritize accounts, then fair progress across account histories.
8. Bound disk usage and collection pages. When storage is full, stop advancing
   tokens and expose backlog state. Do not evict unacknowledged financial data.
   Recover invalid/expired tokens through a new explicit snapshot generation.
   Apply any absence reconciliation only after a complete, validated snapshot
   of its declared authorized scope; interrupted scans cannot imply deletion.

History selection may expand or shrink. Expansion starts a backfill for the new
scope. Reduction cancels/purges unaccepted data outside the new consent, fences
old batches, and retains previously imported Sure history under the documented
retention policy. Authorization revocation and disappearance from a query are
not instructions to erase the family's ledger.

## 4. iOS background execution and packaging

Create an iOS-only `FinanceKit Extension/` target, proposed bundle ID
`am.sure.insights.financekit-extension`. Implement an `@main` type conforming to
`BackgroundDeliveryExtension` with `didReceiveData(for:)` and `willTerminate()`.
The entry points call the same injected collector/outbox services used by
foreground sync; they do not construct views or require `FinanceDataStore`.

In `Project.json`, use an **ExtensionKit extension** product, verifying the
installed XcodeGen support for `extensionkit-extension` and the generated
embedding location against Apple's installed template. That template uses
`EXAppExtensionAttributes.EXExtensionPointIdentifier =
com.apple.financekit.background-delivery`; do not substitute a WidgetKit or
legacy `NSExtension` declaration. Confirm the generated archive embeds it as an
ExtensionKit extension and preserves installation on the host's older minimum
OS. This packaging check is an early release gate.

Add the FinanceKit managed entitlement to the extension and retain it on the
host. Provision both identifiers with Apple-approved capability access. Add
`group.am.sure.insights` to both targets, plus a dedicated Keychain access group
for the device signing key. Configure these through project/entitlement source
files, not a committed generated project. Update the financial-data purpose
string to describe selected server sync. App Group files contain outbox state,
not general OAuth/API-key credentials. [Apple setup sample][apple-extension]

After foreground authorization and opt-in, synchronously register all required
data types with `enableBackgroundDelivery(for:frequency:)`. Proposed starting
frequency: `.hourly` for transactions and balances, `.daily` for account changes.
Every callback checks account history before children, so account dependencies
are recovered even between account-specific deliveries. Measure these choices
on hardware. The API's hourly/daily/weekly values describe expected minimum
intervals when data changes; larger intervals provide larger processing windows.
They are not timers, and unchanged data produces no callback.
[Frequency semantics][apple-frequency]

`didReceiveData` commits essential state and schedules transfers before
returning. `willTerminate` cooperatively cancels collection and saves already
complete work; correctness must also survive termination without that callback.
There is no fixed processing-duration assumption.

Use file-backed background `URLSession` uploads with the App Group
`sharedContainerIdentifier`, stable distinct session identifiers for originating
processes, and delegate-based completion. Transfers can continue after extension
execution ends. The host handles
`application(_:handleEventsForBackgroundURLSession:completionHandler:)`, restores
the corresponding session, durably records events, and calls the completion
handler on the main actor after `urlSessionDidFinishEvents`. Only one process
owns a session at a time. Avoid one upload per transaction and long chains of
completion-triggered tasks; submit a bounded group of reasonably sized files.
[Background networking][apple-networking]

Add host `BGProcessingTask` recovery for queued retries/backfill and a short
`BGAppRefreshTask` for receipt/status reconciliation if useful after measurement.
Register handlers during launch, list permitted identifiers, declare only the
needed `processing`/`fetch` background modes, and implement expiration handlers.
These are opportunistic recovery paths; `UIBackgroundModes` alone does not make
FinanceKit execute. Do not depend on silent APNs, a visible notification,
continuous execution, or a widget. Foreground refresh/Sync now remains a recovery
path. Background uploads without further FinanceKit changes must be tested.

Document and test offline servers, private LAN/VPN reachability, background
restrictions, low power, reboot before first unlock, and force quit. In
particular, user force quit can cancel background URLSession work; do not promise
recovery without reopening in that state. The normal no-open requirement is
an authorized, enabled installation under OS-permitted background execution.
[Force-quit behavior][apple-session]

## 5. Authentication, consent, and destination isolation

Use the existing OAuth bearer or `X-Api-Key` authorizer only for foreground
provider enrollment, mapping, administrative status, and revocation. Require
`read_write` and the user's family permissions. Insufficient scope is a 403
remediation state, not bad credentials. Existing read-only connections keep
working and cannot enroll until authorized for writes.

Recommended background credential: a device-generated signing key registered
with Sure, scoped to one enrollment and approved account mappings. Store its
private material in the shared Keychain as
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, without user-presence gates
that would prevent unattended use. Rails stores the public key and revocation
state. Do not grant this key general financial reads or writes, and do not share
the main app's refresh token with the extension. This avoids cross-process
refresh rotation and expiry of queued bearer tokens.

Apple's background sessions automatically follow redirects and do not invoke
the normal redirect decision delegate. Therefore plaintext financial upload
files with general bearer credentials are not an acceptable default. Design
an authenticated **encrypted and signed batch envelope** using a reviewed,
standard cryptographic format/library supported by CryptoKit and Rails:

- Enrollment over authenticated HTTPS pins a server upload encryption public
  key and key ID. Encrypt financial content to that key before creating files.
- Sign the exact serialized envelope, including ciphertext digest, protocol
  version, server identity, connection ID, device generation, batch UUID, and
  sequence. Use non-secret key identifiers for routing; send no general API key
  or OAuth token on background uploads.
- Server verifies enrollment, signature, size, generation, allowed accounts, and
  replay state before accepting data. Responses must be authenticated receipts
  bound to the batch/digest, so a redirect target cannot forge acceptance.
- Version the envelope, publish cross-language test vectors, protect server
  decryption keys, and define backup/rotation and compromised-device revocation.
  Retain prior server key versions long enough for queued files or force safe
  re-encryption from retained outbox data. Never silently trust a changed key.

This cryptographic envelope is proposed new protocol work, not an existing Sure
capability. A security-reviewed interoperable envelope and redirect test are
release gates. A bounded in-extension URLSession with redirects rejected may
serve the initial feasibility spike; it cannot stand in for verified durable
background transfer in the finished feature. [Networking limits][apple-networking]

Persist a consent/enrollment generation in the App Group. Changing server,
user/family, selected accounts, logout, or disconnect fences pending work,
cancels matching tasks, and removes access to old signing material. Never
retarget queued files to a new host. Online disconnect revokes server acceptance
first; offline disconnect stops local work immediately and clearly records that
server revocation is pending. An already accepted upload cannot be recalled.
Server-side revocation must reject later batches and prevent queued, unapplied
batches from importing. Preserve existing ledger entries unless the user uses a
separate explicit delete workflow.

Protect database/WAL/files for locked-device use after first unlock and exclude
financial staging from backups. Minimize staged fields and delete acknowledged
payloads promptly. Logs, errors, analytics, and support exports contain counts,
state codes, and timings, never payloads, merchant strings, amounts, or keys.
Document server processing/enrichment behavior in consent: uploaded data enters
Sure's configured workflows, including any configured remote enrichment.

## 6. Sure backend implementation

### Models, constraints, and provider registration

Add migrations and matching models for:

- `FinancekitItem`: family, enrolling user, stable connection identity, active
  device public key/generation, revoked/paused/setup states, consent/protocol
  versions, last contact, last data observation, last accepted batch, and last
  completed import. Use server timestamps for operational health.
- `FinancekitAccount`: parent item, source account UUID, confirmed Sure account
  type, institution/display metadata, currency, booked/available observations
  with dates and directions, source availability, and `AccountProvider` link.
  Unique `(financekit_item_id, source_account_id)`; database-enforced
  cross-family isolation and one publishing device per canonical account.
- `FinancekitBatch`: connection/generation/batch UUID, exact digest, sequence,
  bounded encrypted payload, receipt state, processing state, errors and retry
  metadata. Unique batch identity and stream sequence; reuse with different
  content returns conflict. Retain small dedupe receipts/tombstones for the
  generation's lifetime even after pruning payloads.
- Source transaction state, either a dedicated `FinancekitTransaction` table
  or equivalently constrained storage: account/source UUID, latest sequence,
  status, tombstone, and canonical Sure entry mapping. Prefer the table for
  ordered updates and deletion lineage rather than an ever-growing JSON array.

Register `Provider::FinancekitAdapter` in `Provider::Factory`, expose institution
metadata and supported confirmed account types, add the Family association and
provider settings metadata/panel, and extend `ProviderConnectionStatus::PROVIDERS`.
Set `source: "financekit"` on imported entries. The external ID must include the
stable connection/account namespace and source transaction UUID; it must survive
credential rotation and ordinary app updates.

Add `FinancekitItem::Syncer`, account/balance processors, transaction processor,
and unlink/revoke behavior. Reuse `Sync`, `SyncStats::Collector`, and downstream
account recalculation. Audit `Family::Syncer` auto-discovery: nightly sync must
only process queued batches or show waiting-for-device state. A web “Sync” action
can retry already received data; it cannot cause Wallet to yield new data.
Do not report a successful fresh sync when no device data arrived.
[Sync discovery][sure-family-sync], [connection status][sure-status]

Expose provider setup through Sure's existing connection UI: create an account
or explicitly link to an eligible existing account in the same family. Require
confirmation of Depository/CreditCard/etc. when FinanceKit metadata does not
prove the subtype. Never classify every liability as Apple Card. For an account
already fed by another provider, require an explicit source transition and
history reconciliation; silently enabling both can double-count transactions.

### Proposed HTTP contract

All paths below are new proposals beneath `/api/v1`, to be finalized and
published upstream before the native implementation uses them.

| Method/path | Authorization and behavior |
| --- | --- |
| `GET /financekit/capabilities` | Normal read auth; protocol/envelope versions, availability, size limits, supported statuses and server identity; old-server 404 means unavailable |
| `POST /financekit/connections` | Normal read_write auth; idempotent enrollment, device public key and consent; returns connection, generation, server encryption key |
| `GET /financekit/connections/{id}` | Normal family read auth; sanitized status and paginated source-account mappings |
| `PUT /financekit/connections/{id}/account_mappings/{source_id}` | Normal read_write auth; explicit link/create decision and expected mapping version; family ownership enforced |
| `POST /financekit/connections/{id}/batches` | Dedicated device-envelope verification; bounded immutable changes; `202` only after durable inbox commit, plus authenticated receipt |
| `GET /financekit/connections/{id}/batches/{batch_id}` | Normal family read auth or scoped signed device request; accepted/processing/applied/failed receipt and sanitized counts |
| `POST /financekit/connections/{id}/device_replacement` | Normal read_write auth plus explicit handover; new key/generation fences old writer and preserves confirmed source identity |
| `DELETE /financekit/connections/{id}` | Normal read_write auth; revoke publishing and cancel unapplied ingestion; preserve imported Sure accounts/history |

Scope every lookup from the authenticated family/enrollment, never client
`family_id`. The signed upload route needs a dedicated authentication boundary;
the existing API base controller accepts normal OAuth/API keys and must not be
weakened globally to accept device credentials. Verify user active state and
family membership on every device request. Handle enrollment response loss with
an idempotency key bound to the registering public key; no undisclosed orphan
connection or replacement credential may be created on retry.

Specify 400 malformed envelope, 401 invalid credential/signature, 403 scope or
feature restriction, 404 unavailable/unknown family-owned resource, 409 identity
or sequence conflict, 413 size limit, 422 semantic validation, 429 retryable rate
limit, and recoverable 5xx. No raw payload echo in error bodies.

The decrypted version-1 batch contains protocol version, connection/generation,
batch identity, sequence, previous sequence, capture time, declared history
scope/snapshot generation, and typed account/balance/transaction upserts and
tombstones. Currency amounts are lossless decimal strings with explicit currency
and credit/debit indicator. Preserve transaction date, optional posted date,
source status/type, merchant/description when present, and balance observation
kind/as-of time. Keep Apple's amount and direction unchanged on the wire; Rails
performs the one documented sign normalization into Sure's expense-positive,
income-negative convention. Balance normalization is a separate, account-kind
rule with explicit liability/overpayment tests. No missing-currency USD fallback,
zero substitutes, `Double` calculations, or invented stable identifiers.

Use the family's declared time zone for ledger dates derived from timestamps;
retain original timestamps for reconciliation. Define decimal precision and
bounds against Sure storage before finalizing the schema, including currencies
with zero/three minor units. Preserve source transaction type as metadata, not
a client-assigned Sure category. Transfer matching and FX remain server-owned.

Inbox acceptance validates a whole bounded batch and persists it atomically.
A durable scanner/job must recover the commit-before-enqueue crash. Accept
out-of-order files into the inbox, but process contiguous sequences under a
connection lock; old sequences cannot overwrite new state. Record missing
sequence as waiting, not success. Apply a bounded batch's canonical changes and
applied receipt atomically, with downstream scheduling through a durable job
outbox/recoverable scanner. Validation failures block that stream explicitly;
repair uses a documented superseding generation/resnapshot, never a silently
skipped sequence. Keep account metadata ordered before dependent transactions.

### Reconciliation, edits, and deletion

Reuse `Account::ProviderImportAdapter` protection of user edits, excluded/import
locked entries, and server-owned categorization. Extend
`Transaction::PENDING_PROVIDERS` and the adapter's hard-coded pending SQL lists
for `financekit`; adding the provider name in only one list is insufficient.
Test every path that clears pending metadata. [Pending handling][sure-transactions]

FinanceKit UUIDs are authoritative within their known scope. Same-ID pending to
booked is an update; preserve user category/name edits while updating the
permitted status. Do not assume UUID stability across reinstall, devices, or
bank reconnection. If a booked record replaces a different pending ID, prefer
proven source lineage; otherwise present a reconciliation suggestion. Add a
strict identity/reconciliation policy to the shared adapter for FinanceKit so
its current amount/date heuristic cannot silently merge two genuine purchases.
Likewise do not automatically claim ambiguous manual/CSV matches.

Explicit source tombstones retract unmodified provider-owned transaction entries
through Sure's audited deletion/recalculation path, retaining source tombstones
so retries cannot resurrect them. Protected/user-modified entries require review
and remain in the ledger with source-unavailable status. Rejected transactions
can retire their matching pending record. Account deletion/revocation unlinks or
marks unavailable and preserves Sure history; it is not a cascade deletion of
financial records. A truncated scan, narrower date permission, or missing page
must never be interpreted as a transaction tombstone.

Provide explicit reinstall/device-replacement mapping. Stop the old generation
on the server before activating the new writer; reconcile confirmed account
identity and transaction lineage before backfilling. If source UUID continuity
cannot be established, require reconciliation instead of asserting cross-device
exactly-once identity.

Update upstream Minitest behavior tests, docs-only rswag request specs,
`spec/swagger_helper.rb`, generated `docs/api/openapi.yaml`, and client/provider
guides. Generate OpenAPI with the upstream documented rswag command. Add
sanitized debug-log health metadata and configurable payload retention, limits,
rate limiting, job retries, and per-family/operator disable controls. Include
staged data in family export/reset/delete lifecycle audits. Deploy migrations
and workers before enabling enrollment; rollback disables new ingestion while
retaining accepted batches and imported ledger records for recovery.

## 7. Native code ownership and user experience

| Area | Planned work |
| --- | --- |
| `App/Domain/FinanceKitSync/` | UI-independent records, generation/identity, mapping and retry policies |
| `App/Domain/Services/` | Narrow history-reading, outbox, upload, receipt, clock and credential seams |
| `App/Infrastructure/FinanceKit/` | Real history adapter, authorization and background registration adapter; preserve current local display connector |
| `App/Infrastructure/ProviderSync/` | Coordinator, App Group database, file transfer delegate, envelope adapter, recovery leases and status persistence |
| `App/Infrastructure/API/` | Typed capability/enrollment/mapping/status DTOs and endpoint clients through injected transport |
| `App/Application/` | Foreground/background composition, session event routing and connection-lifecycle cancellation |
| `App/Features/Accounts/` | Explicit publish setup, account mapping and accessible sync status with injected services |
| `FinanceKit Extension/` | Only extension entry point and composition; compile an explicit extension-safe subset of domain/infrastructure files |
| `Tests/SureTests/` | Mirrored domain, API, state, persistence, lifecycle and mapping tests |

Do not move this implementation into Watch's `Shared/` directory or compile
`App/Features` into the extension. Reuse selected app-owned domain/infrastructure
sources through explicit `Project.json` membership; extract a small local module
only if duplicate source membership becomes unwieldy. The App Group identifier
can live in the app-owned sync infrastructure compiled into both targets.
Document this app/extension ownership exception in `AGENTS.md` and README when
implemented. Leave existing app/watch shared value types unchanged.

Use a persisted observable feature store exposing disabled, needs authorization,
needs enrollment/mapping, collecting, queued, uploading, processing, up to date,
stale, paused, and failed states. Show distinct last device contact and last
completed server import times. Never show “up to date” from a successful local
read or queued upload. Use a semantic persistent sync Toggle, Sync now action,
retry/remediation and disconnect controls, Dynamic Type and VoiceOver labels.
Background registration is rechecked after relaunch; UI preference alone is not
proof that delivery is enabled.

Once linked, show the Sure account as canonical and suppress the duplicate local
Wallet row using the explicit source-to-Sure mapping. Keep unlinked Wallet
accounts visible as local. On another platform, synced records arrive from Sure
normally. Preserve account transactions' 31-day and Recent activity's 7-day
navigation rules; export scope is independent of these presentation windows.

## 8. Delivery sequence and acceptance gates

1. **Backend provider and contract (blocks native implementation).** Complete
   [Sure #3485](https://github.com/we-promise/sure/issues/3485): ship models,
   strict intake/receipts, enrollment/revocation, account mapping, provider
   adapter, ordered processing, status UI/API and tests behind a disabled
   feature flag. Finalize the interoperable upload protocol and document
   privacy, cryptography, replacement and deletion behavior. Verify ingestion
   and recovery with a synthetic client before starting iOS implementation.
   No native fallback to generic transaction writes if the contract is absent.
2. **Native background feasibility against the merged contract.** On a provisioned physical
   iPhone with SDK 26.5, validate the extension bundle/entitlements, authorization
   inheritance, locked-device reads, independent extension execution, and file
   uploads after extension exit. Verify host background completion ownership,
   redirects, resource limits and old-iOS host installation. Use sanitized test
   uploads to the controlled Sure deployment and verify the published envelope
   interoperability vectors. This gates broader native implementation and UI
   work; physical-device validation remains required before native release.
3. **Native durable sync core.** Add typed DTOs, source history adapter, outbox,
   credential/envelope handling and deterministic tests. Adopt the actual merged
   server SHA in `SureContractBaseline.md`, fixtures and compatibility tests.
   Update the narrow provider-ingestion exception in AGENTS/README/baseline.
4. **Background target and recovery.** Add target, groups, signing, registration,
   background transfer and BGTask lifecycle. Update CI path filters for the
   extension/new directories, extension build checks and archive validation.
   Verify the runner's SDK supports the chosen APIs; reconcile CI's existing
   Xcode 26.2 pin and AGENTS SDK wording with the verified 26.5 toolchain when
   adopting it. All generated configuration remains derived from Project.json.
5. **Opt-in UX and canonical accounts.** Implement selection, linking,
   foreground bootstrap, visible status, duplicate-row suppression, pause,
   disconnect, reauthorization and replacement flows. Keep existing data/design
   intact when disabled or connected to an unsupported server.
6. **Hardware/TestFlight pilot.** Enable for a small controlled cohort after
   signed archive validation. Observe latency distributions, callback/transfer
   failures and backlog age using non-financial metrics. Tune batch sizes and
   delivery frequencies from evidence, then enable wider rollout.

Required automated coverage:

- Swift Testing with injected history, clock, credentials and transport: empty
  and multi-page history, initial backfill, inserts/updates/deletes, token reset,
  lost acknowledgments, every crash boundary, duplicate scheduling, simultaneous
  app/extension workers, disk pressure, expired leases and cancellation.
- Contract fixtures for success/empty/malformed/errors, digest conflicts,
  out-of-order sequence, wrong-family/account/generation, revoked keys,
  encryption/signature/receipt verification and key rotation.
- Money/date tests for debit/credit purchases, refunds, card payments,
  liabilities/overpayments, available versus booked balances, negative/zero/large
  values, month/time-zone boundaries, currencies with zero/three minor units,
  and pending-to-booked updates with/without UUID continuity.
- Rails Minitest for import idempotency, source isolation, user edits,
  ambiguous matches, protected deletions, concurrent writers, atomic receipts,
  queue recovery, permissions, user deactivation and enrollment revocation.
  Regression tests must cover all modified shared adapter paths.
- iOS and macOS tests/builds, Watch build/regression checks, iOS extension
  build and signed archive inspection. Regenerate after source/config changes.
  Use Bitrig builds and simulator interaction for accessible setup/status UI;
  simulator fakes cannot validate real FinanceKit delivery.

The hardware exit test is explicit: enroll once, leave the app in the background
without reopening it, introduce an authorized Wallet transaction/change, and
verify a completed import on Sure. Repeat with the phone locked after first
unlock, an offline server that later recovers, no additional Wallet change,
process termination, duplicate delivery, and server processing failure. Verify
one canonical transaction, correct status/balance, and no lost checkpoint.
Characterize force quit/reboot/restricted-background behavior separately and
surface the necessary recovery honestly. No timing guarantee is inferred from
a single successful run.

Planning validation: inspected the pinned upstream source/OpenAPI, current
native implementation, Apple's documentation, and the installed SDK/template.
No app builds or tests are required for this documentation-only change; none
were run. The physical-device spike and all implementation checks above remain
work to do, not validated capabilities of the current app.

[apple-extension]: https://developer.apple.com/documentation/financekit/implementing-a-background-delivery-extension
[apple-frequency]: https://developer.apple.com/documentation/financekit/financestore/updatefrequency
[apple-networking]: https://developer.apple.com/documentation/foundation/downloading-files-in-the-background
[apple-session]: https://developer.apple.com/documentation/foundation/urlsessionconfiguration/background(withidentifier:)
[sure-generator]: https://github.com/we-promise/sure/blob/5594f8bc94c8e659838cac70d826bbcaeaa3bae2/docs/api/rails_provider_generator.md
[sure-factory]: https://github.com/we-promise/sure/blob/5594f8bc94c8e659838cac70d826bbcaeaa3bae2/app/models/provider/factory.rb
[sure-import]: https://github.com/we-promise/sure/blob/5594f8bc94c8e659838cac70d826bbcaeaa3bae2/app/models/account/provider_import_adapter.rb
[sure-openapi]: https://github.com/we-promise/sure/blob/5594f8bc94c8e659838cac70d826bbcaeaa3bae2/docs/api/openapi.yaml
[sure-family-sync]: https://github.com/we-promise/sure/blob/5594f8bc94c8e659838cac70d826bbcaeaa3bae2/app/models/family/syncer.rb
[sure-status]: https://github.com/we-promise/sure/blob/5594f8bc94c8e659838cac70d826bbcaeaa3bae2/app/models/provider_connection_status.rb
[sure-transactions]: https://github.com/we-promise/sure/blob/5594f8bc94c8e659838cac70d826bbcaeaa3bae2/app/models/transaction.rb
