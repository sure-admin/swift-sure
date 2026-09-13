# Read-only client architecture

Sure is the system of record. The client presents server resources and maintains
a private local cache. The only on-device aggregation is the separately labeled
Wallet onboarding preview, permanently disabled after the first successful Sure
connection. Future Wallet ingestion must send source transactions to Sure and
leave aggregation to the server.

## Sessions and access

`SureConnection` owns connection-screen drafts and user intents. It uses the
`ConnectionAuthenticating` seam. `AuthenticationCoordinator` owns bounded,
cancellable attempts; `CommittedConnection` owns verified identity transitions,
credential replacement, rollback, and logout. API-key, OAuth, and mobile SSO
adapters keep their distinct wire contracts while sharing commit and cleanup.
Refresh rotation retains the persisted connection ID. A fresh login gets a new
ID, even for another user on the same server. Legacy sessions derive the previous
cache namespace once, then persist it through subsequent rotations.

Every backend request passes the final `BackendAccessGate` transport check.
`CachedFinanceRepository` applies offline-read policy above endpoint clients.
Candidate verification always uses the live gated path, never cached reads.
Entitlement loss preserves credentials and downloaded records.

## One cache

`ServerReadCache` is an actor with protected atomic writes, schema versioning,
per-entry fetch dates, and a shared limit of 256 entries / 64 MiB. Oldest-written
entries are evicted first. Complete account, balance-sheet, budget, insight,
summary, transaction-window, and remote-conversation reads use this store.
Transaction keys include the account and both inclusive dates; partial pagination
never becomes a complete cached window. A small latest-window reference allows
older downloads to reopen with their actual coverage dates when the rolling
window has advanced; it never claims the new requested window is complete.
Successful empty reads replace deleted
server records. Disk-write failure does not discard a successful live response.

Cache namespaces bind normalized server URL and committed connection ID. Logout
increments an invalidation generation before erasure, preventing late writes from
recreating old data. Cleanup failures remain actionable while the session stays
signed out. Legacy Overview snapshots migrate asynchronously; their unrecorded
transaction coverage is usable only as a display preview, never as proof that a
requested window is complete. Old response archives are removed on logout or a
committed connection change.

Only connectivity failure or entitlement suspension permits cached fallback.
Authentication, scope, malformed-response, validation, and server errors remain
distinct. Each resource exposes typed failure, source, and fetch date. A partial
refresh does not make other resources appear newly fetched.

## Financial state

`FinanceResource` owns one resource's value and loading/failure/freshness state.
`FinanceSyncCoordinator` coalesces screen refreshes while allowing independent
publication. `ReportingPeriodStore` owns Gregorian month selection.
`FinanceDataStore` exposes a screen projection rather than deriving financial
reporting rules. Overview requests seven days of recent transactions; account
screens request 31 days. Browsing historical summaries does not expand those
windows.

`financial_summary` reuses IncomeStatement's user/account scope, exclusions, and
FX behavior. Amounts remain Decimal, including sub-minor-unit FX precision. The
server's as-of date determines chart completeness and comparisons. The client
only formats and folds chart points for presentation.

## Other session boundaries

Push cleanup includes connection identity, not just host. A Keychain installation
secret is unique per server and survives logout. Its backend digest proves device
continuity when registration changes users. Transfers create a new row ID, so
old delivery jobs and delayed deletes cannot target the replacement. Legacy
registrations without a proof must first be enrolled or removed by their original
owner; a token alone never authorizes transfer.

Watch snapshots carry a persisted installation stream and increasing revision.
Logout clears the Watch even if its previous snapshot has a future timestamp.
The local Assistant receives explicit source, freshness, and incomplete-window
context and never claims to have queried Sure. Server chat polling uses bounded
backoff.

## Composition and tests

Application-owned connection, finance, device, and analytics assemblies construct
concrete services. Features consume service seams. The unit-test app host does
not instantiate production services. A separate UI test executable renders
production views with memory-only fixtures and checks source boundaries, retry,
and accessibility descriptions on iPhone and iPad. CI runs those tests, the app
and Watch suites/builds, and a focused SwiftLint correctness gate.
