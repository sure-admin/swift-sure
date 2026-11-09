# Device-first onboarding and optional Sure connection

Status: proposal for review; no app implementation in this change.
Prepared September 9, 2026, against the current client and the upstream revision
in [SureContractBaseline.md](SureContractBaseline.md).

## 1. Product decision

Make Sure a useful, free personal finance app before a person connects a server.
An eligible Apple Card customer on iPhone should be able to authorize Wallet,
understand spending, browse accounts and transactions, and ask private questions
without creating a Sure account, entering a server URL, or supplying an AI key.
Sure becomes an optional household finance destination.

The free core has no trial, subscription gate, transaction allowance, AI token
allowance, or dependency on a hosted Sure service. Apple permissions, eligible
hardware, available Wallet history, and model readiness remain real constraints.
“Independent of Sure” does not mean Wallet never needs its providers to refresh,
or that an Apple model is already downloaded on every device. Previously loaded
data and deterministic summaries must work offline.

Recommended product boundaries:

- Wallet is authoritative for the records it shares. The device stores a local
  projection and computes explicitly scoped summaries from those records.
- Sure is authoritative for household records, budgets, categorization, and its
  balance sheet. It remains the authority for cross-currency net worth.
- Before connection, all generative assistance uses Apple's on-device model.
  When that model is unavailable, useful calculations and guided summaries still
  work. There is no remote AI fallback.
- After connection, on-device assistance remains the default. Sending a question
  to Sure is a visible, explicit choice with separate conversation history.
- Connecting a server, uploading Wallet data, and sending a remote AI question
  are three distinct actions. None implies consent to the others.
- Keep financial editing out of the initial release. Budget is an honest preview
  locally. Optional Wallet upload is a later, narrowly defined financial write
  workflow, rather than permission to add arbitrary account or transaction edits.

This intentionally changes the client product's server-first positioning in
upstream's [client overview][sure-clients]. It does not change the server contract.
Before implementation, record the accepted source-of-truth and visual-scope
exceptions in AGENTS.md and the client-policy sections of the contract baseline.
The existing policies and upstream pin are unchanged by this planning document.

## 2. Findings in the current app

| Boundary | Current implementation | Required change |
| --- | --- | --- |
| Entry | `App/Application/ContentView.swift` gates iOS tabs on `connection.isConfigured`; Mac shows tabs without that gate. | Onboarding completion and Sure authentication become independent. All platforms can enter the app without a server. |
| First screen | `Features/Connection/SignInView.swift` leads with credentials and a server identity. | Use a short local-first welcome; retain sign-in inside the optional Sure connection flow. |
| Finance state | `Features/Finance/FinanceDataStore.swift` checks Sure configuration and fetches balance sheet, accounts, transactions, budgets, and insights together. | Separate local and household state; unavailable server features must not stop local refresh or render as local failures. |
| Wallet | `AppleCardConnectionStore` loads authorized accounts; `AccountsView` renders Wallet only inside the loaded Sure branch. | Make Wallet access and its accounts independently visible and refreshable. |
| Wallet history | `FinanceKitAppleCardConnector` loads transactions and filters in memory; a request with no account ID returns an empty array. | Support all-account local Recent activity, bounded queries, and a persistent, reconciled local read model. |
| Classification | `LocalFinancialTransactionMapper` maps every credit to income; presentation loses source status and transaction type. | Preserve provider semantics before building spending, income, insights, or AI context. |
| Overview | Uses only Sure data, including a server net-worth card and income/savings metrics. | Build a useful Wallet overview with truthful scope, status, and history coverage. |
| Assistant | Normal send already uses Foundation Models, but its context is `FinanceDataStore`; long-press sends to Sure. One message list spans destinations, and saved conversations are server-only. | Inject source-aware context, expose model availability, split local/server history, and replace hidden destination selection. |
| Persistence | Sure has an identity-bound snapshot file with file protection and backup exclusion. Wallet accounts are memory-only; local conversation history is memory-only. | Persist Wallet projections and local conversations separately from Sure credentials/cache. |
| Notifications | Overview's urgent-insight toggle drives APNs subscription infrastructure. | Make server notifications explicitly server-only; do not request them in local onboarding. |
| Watch | Receives only `BackendInsight` projections; Sure disconnect sends an empty snapshot. | Support selected local summary snapshots without erasing them merely because Sure disconnects. |
| Test coverage | There are useful mapper, auth, finance-store, assistant, and Watch tests. The concrete FinanceKit connector is deliberately unavailable in simulator. | Add offline provider fakes and real-device entitlement/Wallet validation; simulator success alone cannot prove FinanceKit works. |

Reuse the existing money/date types, transaction navigation, theme, credential
lifecycle, and typed Sure clients. This does not call for a repository rewrite.

## 3. Verified platform constraints

Apple documents FinanceKit's US financial-data access on iPhone, including Apple
Card, Apple Cash, and Savings, with exclusions for Apple Card Family participants
and Apple Cash Family children. Users choose accounts and the shared history
range. Entitlement approval is assigned per bundle ID. The existing entitlement
file is not proof of distribution approval. [Apple FinanceKit requirements][financekit]

Treat iPhone as the initial automatic Wallet-ingestion device. Do not promise
direct Wallet ingestion on iPad or Mac based on the framework compiling. macOS
and watchOS FinanceKit access is unavailable in the inspected SDK. Runtime
availability is the deciding signal on iOS; do not guess eligibility from region
or account name alone.

The installed SDK reports 26.5. Foundation Models is guarded at iOS/macOS 26;
FinanceKit history APIs are available before the app's iOS 18 minimum, and its
background-delivery APIs are iOS 26 additions. Keep deployment targets at iOS 18,
macOS 15, watchOS 11 and use no SDK 27 APIs. CI currently selects Xcode 26.2;
reconcile that documentation/toolchain difference deliberately if an implementation
needs a later API. The proposed baseline does not require a 26.5-only API.

`SystemLanguageModel` availability depends on device support and Apple
Intelligence readiness. Distinguish unsupported OS/device, Apple Intelligence
disabled, model not ready, and unsupported language from a generation failure.
Recheck when the app becomes active. [Apple model documentation][model]

The broad phrase “anyone with Apple Card” requires a fallback beyond FinanceKit.
Recommended follow-up: an entirely local Apple Card CSV statement importer on
iPhone, iPad, and Mac. Validate current export formats and access paths before
committing to that feature. Imported statements cannot imply live balances or
current pending activity. Until that ships, market automatic access only for
eligible iPhone customers; unsupported customers get a useful explanation and
can explore or optionally connect Sure. This platform gap is a product decision,
not a reason to quietly make a server mandatory.

## 4. Onboarding journey

Target: reach a real, useful overview immediately after Wallet authorization and
the initial bounded load. Avoid a carousel of feature advertisements.

1. **Welcome.** “Your money, on your device.” Explain free local use and optional
   household connection. Primary action: “Use Apple Wallet” when available.
   Also offer “Explore the app” and a quieter “Connect to Sure.” No email field,
   hosted-demo connection, notification prompt, tracking prompt, or AI consent
   detour is needed for local entry. Do not conflate Wallet permission with Sign
   in with Apple, which is a separate server authentication option.
2. **Permission explanation.** Briefly describe accounts, balances, and
   transactions, their local use, and the user's control over shared data.
   “Continue to Wallet” invokes Apple's authorization UI once, following a tap.
   Update the current purpose string, which refers only to Accounts, when this
   onboarding is implemented. Do not duplicate Apple's account/range picker.
3. **First load.** Show progress by meaningful stage: accounts, recent activity,
   then spending summary. Permit cancel/continue without data. Render available
   sections as they become ready; do not wait for an LLM or historical backfill.
   If permission succeeds but no accounts are shared, explain that specifically.
4. **First value.** Open Overview with Wallet balances, this month's posted
   spending, pending activity, and recent transactions. Offer “Explain my
   spending” using actual coverage. Explain privacy inline in Assistant when it
   is first used. Optional Watch sharing happens later in Settings.
5. **Return visits.** Restore the selected local view and protected data, validate
   authorization, and refresh incrementally. Do not replay onboarding after a
   Sure logout or a cancelled authentication attempt.

“Explore the app” opens honest empty states and general local help. Synthetic
examples, if used in the Budget preview, are explicitly labeled and never enter
finance stores, assistant context, export queues, or Watch snapshots. Exploration
must not connect to `demo.sure.am` behind the scenes.

| Condition | Expected experience |
| --- | --- |
| Permission denied or cancelled | Continue into the app, with a persistent but quiet Wallet setup entry. No repeated system prompt or forced Sure sign-in. |
| Authorized, zero shared accounts | “No accounts shared”; describe how to manage access. Preserve navigation and exploration. |
| Only recent history shared | Show the available scope; suppress comparisons needing more data. Never equate the earliest transaction with the permission start date. |
| No activity within a successfully loaded window | Show zero activity for that window; keep this distinct from unknown/incomplete coverage. |
| Refresh fails | Keep previously authorized cached data with its timestamp; show per-section retry. Do not turn failure into zero spending. |
| Access revoked or an account removed | Hide/purge the affected projection and derived context when detected, cancel its work, clear its history cursor, and propagate removal to enabled companion destinations. |
| FinanceKit unavailable | Explain support limits; retain exploration and optional connection. Offer statement import only once it is implemented. |
| Existing Sure user upgrades | Open their existing household view without another onboarding gate. Offer Wallet locally without changing their server, credentials, or notification preferences. |
| Server sign-in fails or SSO needs account setup | Keep the local app accessible; present the existing SSO handoff within the optional connection flow. |

## 5. Feature-by-feature product behavior

| Surface | Free device experience | With Sure connected | Scope and constraints |
| --- | --- | --- | --- |
| Overview | Wallet balance summary, posted purchases/spending, refunds, separately labeled pending amount, recent activity, merchant breakdown, and data-derived highlights. | Household Overview retains server accounts, transactions, budget/insight data, and authoritative net worth. | A visible source selector appears only when both sources exist. Preserve current card styling and tab order. |
| Net worth/account chart | Show “Wallet balances” or “Card balance,” with balance as-of dates. Group currencies; show amounts owed distinctly from assets. | Net worth continues to come from Sure's balance sheet. | A card balance is not complete net worth. Never combine Wallet balances with server net worth. |
| Income/savings rate | Omit from card-only summaries. Show card payments/refunds under their actual meaning. | Preserve supported household reporting from typed server data. | Card credits do not establish salary or a household savings rate. |
| Month navigation/trends | Current month by default; previous months within loaded/shared coverage, merchant totals and comparable-period changes. | Existing household month navigation. | Use month-to-date versus equivalent prior-month days, or label unequal periods; no invented zero months. Keep account/Recent activity drill-down defaults unchanged. |
| Accounts | Authorized Wallet accounts, native balances or “Balance unavailable,” provider/source labels and manage-access action. | Server accounts remain visible in the household source; local accounts remain reachable independently. | No misleading add-account tile that only opens server settings. Support eligible accounts returned by Wallet, not hard-coded Apple Card names. |
| Account transactions | Rolling last 31 days, source-correct signed display, pending/posted status, accessible rows and read-only detail. | Same navigation into server history. | Scope includes source identity as well as account ID. An identical UUID in two sources must not collide. |
| Recent activity | Rolling last 7 days across authorized local accounts. | Across household accounts in household mode. | Never concatenate both sets without reconciliation. The current nil-account local query must be fixed. |
| Search/filter/detail | Local merchant/text search and status/category filters within the loaded window; display that window. Details show source, dates, amount and status. | Continue/extend read-only server search through documented queries. | Search outside loaded history requires explicit fetching, not a false “no results.” Detail improvements are a planned addition, not an existing capability. |
| Categories | Deterministic mapping from provider type and available merchant category codes, with an explicit uncategorized remainder. | Sure categories remain server-owned. | Current “Purchase” transaction type is not a shopping category. Label locally derived categories; AI does not silently write them. |
| Insights | Deterministic spending summaries and merchant changes with drill-through evidence; optional on-device explanation. | Sure insights shown separately with their own loading/gating state. | Start with straightforward summaries. Possible recurring payments require enough history and a “possible” label; no fabricated urgency or due dates. |
| Assistant | On-device questions over scoped, typed local data; persisted local chats; useful guided summaries without AI. | Optional explicit Sure conversations plus continued local assistance over allowed cached context. | No hidden long-press remote send or automatic escalation. See section 7. |
| Budget | A polished “Plan together with Sure” preview explaining category limits, remaining budget and household tracking. A link back to real local spending gives immediate utility. | Actual read-only budgets, including empty, unavailable, preview-gated and failed states. | No invented available-to-spend number, pretend progress ring, or implication that connecting creates a budget. Local budget creation is outside this proposal's first release. |
| Notifications | None requested during onboarding. A later optional local recap can summarize known data when refreshed. | Explicit urgent Sure insight notification setting using current APNs infrastructure. | No payment-due alert without authoritative due dates, no guaranteed background refresh/delivery claim, and no APNs registration/upload in never-connected use. |
| Watch | Opt-in transfer of a small local summary/highlight snapshot from iPhone, with source and freshness. | Existing server insights remain a separate selectable source. | Watch is a companion reader, not a FinanceKit or LLM host. Source removal must eventually clear the companion cache. |
| iPad/Mac | Ungated navigation and local help. A future statement-import workflow provides personal data without Sure. | Existing household features and on-device AI on supported hardware. | No automatic iPhone-to-Mac/iPad financial sync in the initial release. Optional personal device sync is separate scope and consent. |
| Settings/privacy | Wallet status, manage access, refresh, local storage usage, delete local data/chats, Watch sharing and optional Sure connection. | Host/account identity, server connection state, notification status and disconnect. | Separate “Disconnect Sure” from “Remove Wallet data” and “Erase local app data.” Explain what remains on the server. |
| Widgets/Shortcuts/exports | Not present in the current app; not a prerequisite for the free core. | No automatic expansion from connecting. | Defer new extensions and exports; any later integration must inherit source/consent/privacy boundaries. |

A teaser should explain an attainable benefit and offer a next step, not occupy
every card. Keep one optional connection invitation in Settings and a contextual
Budget preview; do not repeatedly interrupt a successful local workflow.

## 6. Data and architecture plan

Model capabilities rather than one global `isConfigured` gate. Compose them in
`Application`; features receive narrow query/action services and observable
presentation state. Proposed names below describe responsibilities, not a
requirement to generate a class for each item.

| Responsibility | Ownership and invariant |
| --- | --- |
| Onboarding state | Feature state plus an injected preferences adapter; persist completion/version separately from credentials and OS authorization. |
| Source identity | Domain values identifying Wallet store/account or Sure server/authenticated identity/account; use source-scoped record keys throughout navigation, persistence and derived results. |
| Capabilities | Independently report Wallet permission/data, local model readiness, Sure session validity, budget access, server chat, server insights and optional upload support. Connection success alone proves none of the optional capabilities. |
| Local financial repository | Infrastructure owns FinanceKit access and an indexed, versioned local store behind domain query protocols. Return domain records rather than `FinanceTransaction` presentation values. |
| Local finance state | Main-actor observable state consumes the repository; no Sure credentials or `ConnectionStateProviding` dependency. Separate per-section load/error/freshness/coverage state. |
| Household finance state | Incrementally retain/refine `FinanceDataStore` and existing API clients for server data; avoid forcing Wallet into `FinanceDataClient.fetchBalanceSheet` or returning fake empty budgets. |
| Summaries/context | Pure domain queries calculate amounts, breakdowns and comparisons once. Overview, Assistant and Watch consume the same validated results. Infrastructure does not read another feature's view model. |
| Assistant composition | Construct local model/context/conversation services at the app root, not inside `AssistantView`. Scope all chat state by destination and, for Sure, authenticated session identity. |
| Lifecycle | Local authorization generations and Sure session generations are separate. Cancel and ignore stale completions after source changes; a Sure logout cannot reset local stores or local chats. |

### Wallet ingestion and durable state

Use an infrastructure-owned SwiftData local store (no CloudKit configuration) as
the initial persistence choice: indexed transaction history and incremental
updates warrant more than a single overview JSON snapshot. Expose value records
at the repository boundary, keep store work off the main actor, and inject an
in-memory/test repository. Reuse the existing protected snapshot approach for
small derived payloads only where it is sufficient. Verify file protection and
backup exclusion for the database, journal/sidecar files and migration artifacts.

Initial ingestion prioritizes accounts, balances, current month and the rolling
31-day window. History reconciliation then consumes per-account inserted,
updated and deleted records. Save data changes and the new history token
atomically; a crash must not advance a token past uncommitted data. Do not claim
full coverage until initial history enumeration has completed. Stream/batch
backfill to avoid loading the complete Wallet store into memory. FinanceKit
supports these history updates and tokens. [History API][history]

Use predicates/limits for interactive range queries. Monitor changes while
active, recheck permission when returning to foreground, and reconcile after
restart. Enable iOS 26 background delivery only after foreground correctness;
older supported systems retain foreground refresh. Background execution is an
optimization, never a requirement for core data access.

Preserve signed money, currency, account kind, source transaction type, pending
status, merchant metadata, transaction date, posted date, and balance as-of time.
Handle pending-to-posted updates and deletions idempotently. If a provider replaces
an ID, do not merge distinct purchases using amount/date alone; validate available
linkage and otherwise let source deletion/update history drive reconciliation.

### Financial rules to settle before displaying local totals

- Store financial values as `Money`/`Decimal`, not `Double`. Keep the provider's
  direction and business classification separate; normalize display sign once.
- Spending means posted purchase debits plus disclosed fee/interest treatment,
  with refunds shown separately and net spending clearly labeled. Card payments
  and transfers are neither earnings nor new purchase spending. Unresolved
  credits/debits remain visible without being guessed into an income category.
- Pending activity is visible separately and excluded from posted totals. Avoid
  counting a transaction twice after posting.
- Prefer posted dates for settled reporting and transaction dates for pending
  activity. Use injected calendar/time-zone rules consistently across summary,
  drill-down and assistant tools. Test travel/time-zone changes explicitly.
- Keep missing balances, partial history, stale data and confirmed zero distinct.
  Carry per-source/per-section timestamps; stop using “LIVE” for cached data.
- Group currencies rather than invent FX. A statement import cannot reconstruct
  today's balance from incomplete historical transactions.
- Merchant category codes can support a deterministic, documented local category
  mapping. Preserve the original value and show coverage/uncategorized amounts.
  Do not turn an LLM category guess into authoritative financial data.

### Privacy, removal and recovery

Store preferences through an injected adapter, secrets through existing Keychain
boundaries, financial projections/chats in protected app storage. Default local
financial data and conversations to backup exclusion; explain that local data
does not automatically appear on a replacement device. Reauthorize/rebuild from
the history Wallet makes available. Delete cache and derived model context on
detected revocation. Do not prompt the model before an authorization check permits
using cached financial context.

Keep local-store deletion separate from revoking Apple's OS permission: clearing
the app's data should suspend ingestion until the user explicitly resumes, or it
would immediately refill. Explain OS access management separately. If protected
storage is locked, defer work rather than treating it as corrupt or empty.

No financial payloads, prompts, credentials or diagnostics leave the app for
analytics. Acceptance telemetry can be local/debug-only, with synthetic test
data. There is no hidden launch-time server health check, SSO discovery, model
request, push registration, or demo data fetch before an explicit connection.

## 7. Assistant behavior and trust

The existing local-send default is a good starting point, but model instructions
alone cannot guarantee accurate money answers. Replace the unstructured dump of
up to 30 transactions with scoped context plus typed, bounded query tools.

- Offer “Summarize this month,” “Show my largest purchases,” and “Compare merchant
  spending” when data supports them. Do not lead card-only users with “Can I
  afford a trip?” because card activity cannot establish affordability.
- Domain queries compute totals, periods and evidence records. Render monetary
  facts in deterministic result cards with transaction drill-through. The model
  explains them; it does not perform authoritative arithmetic or invent records.
  Validate references and avoid treating unverified narrative numbers as facts.
- Include source, loaded/shared coverage, currency and freshness in context.
  Bound query results and context size; summarize long conversations and offer
  continuation when limits are reached. Cancellation/refusal/error keeps the
  user's draft or retryable message, with no automatic remote retry.
- Treat merchant descriptions, notes and server text as untrusted data. Tool
  permissions enforce local-only reads; prompts cannot grant networking or writes.
- When Apple Intelligence is unavailable, show why and provide the same supported
  summaries via explicit buttons and templated results. Do not imitate open-ended
  chat with canned guesses. Never suggest connecting Sure is required to see
  spending totals.
- Persist local conversations locally, with delete controls. Starting a Sure
  conversation creates a separate thread; local transcript/context is never
  silently copied. A server conversation is scoped to server and account identity.
- Once connected, use a semantic destination picker or explicit “Ask Sure” action
  and a visible destination label beside Send. Model capability failures must not
  change the selected destination. The local option remains available.
- Remote copy explains that the question goes to the selected Sure instance and
  its configured AI service; connecting does not imply Apple-only processing on
  that server. Show server chat availability separately from backend insights.
- In the first connected release, remote chat receives only the user's explicitly
  submitted question and its server conversation. There is no automatic Wallet
  attachment. A future “Include local summary” feature would need a preview of
  the exact content and a separate explicit send action.

Use Foundation Models availability checks and bounded sessions described by
Apple's [generation guide][generation]. Evaluate supported tasks with synthetic
financial scenarios on real supported devices; deterministic unit tests should
test services and boundaries rather than demand exact LLM wording.

## 8. Optional Sure connection and Wallet upload

### Connection first: useful without upload

Enter from Settings, the welcome's secondary action, or Budget. Show the server
the user is choosing and retain existing passkey, API-key and SSO flows. Remove
the implication that `demo.sure.am` is the user's production destination. Never
upload personal data to a demo server automatically.

On success, show the available household data in a separate source. Do not
automatically change a local user's active overview, consent, AI destination or
Watch sharing. Preserve an existing server user's household default on upgrade.
If budgets/insights/chat are unavailable, explain the specific feature condition
rather than claiming authentication failed. A read-only account still gets its
authorized read features.

Disconnect cancels household work, performs the existing token/push cleanup,
clears household cache/history, and returns to local finance. Transient server
failure retains identity-bound cache with stale labels. Switching hosts or
identities isolates all server cache, chat, upload mapping and queued work.

### Upload: a separate deliverable

The request establishes the desired optional sync direction. Recommend a first
upload release that **copies selected Wallet records to Sure** and then reads
household data back. Do not describe it as bidirectional synchronization with
Apple Wallet: the client cannot edit Wallet's financial records.

The inspected [pinned OpenAPI][sure-api] provides meaningful building blocks:

- Account collection/detail GET operations; it does not document a direct
  account-create POST at `/api/v1/accounts`.
- Transaction POST supports `external_id` plus `source` and returns an existing
  transaction for the account/source-scoped idempotency key. PATCH/DELETE also
  exist; repeated creation is not evidence of update reconciliation.
- Import preflight, imports, and import sessions with session/chunk idempotency
  and publishing are documented. These are candidates for initial account/history
  import, subject to verifying the actual NDJSON schema and mapping semantics.
- `/api/v1/syncs` describes server sync status; it is not a generic Wallet upload
  protocol.

Do a bounded contract spike before writing the uploader: inspect pinned request
specs/import schemas and prove lossless amounts, sign semantics, account creation
or mapping, source identity, duplicate readback, updates and failure recovery.
Use the [transaction guide][sure-transactions] for scope/sign context. Choose the
documented import pipeline where it meets the workflow; do not implement a custom
server pipeline through chat or invent an endpoint. Record any required upstream
change and update the pin/fixtures together if adopted.

The user's upload journey must make these steps concrete:

1. Identify the connected server and household/account context; explain who may
   gain access to uploaded financial data, including configured server processing.
2. Select local accounts and an available history range. Upload stays off by
   default, including after sign-in or adding a new Wallet account.
3. Map each account to an existing Sure account or a contract-supported new one.
   Warn about an existing provider/import for the same card. Never assume account
   names are unique or matching names establish identity.
4. Preview counts, date coverage, account mapping, excluded/pending records, and
   known duplicates locally. Explicitly authorize upload before a *remote*
   preflight; preflight itself transmits financial data even if it creates none.
5. Persist a consent-bound, restartable upload job. Show progress, per-record
   failures, pause/cancel, bounded retries and readback verification. Do not mark
   all rows synchronized because one HTTP request succeeded.
6. Offer “Keep this account updated” only after incremental reconciliation passes
   its acceptance gate. Recheck consent, authorization and destination identity
   before every send. New accounts or an expanded historical scope need selection.

Use stable source/account/record keys, a durable mapping to server IDs, content
versions and checkpoints. Retry after a lost response using the same idempotency
key. Namespace keys to avoid multiple-device collisions; if FinanceKit identifiers
are not stable across reinstalls/devices, automatic repeat import is not safe
until reconciliation or a user-reviewed mapping resolves that uncertainty.

Do not overwrite Sure's user-edited categories, names, notes or tags as a side
effect of refreshing provider-owned amounts/status. Do not automatically delete
server history because Wallet access was revoked or a record disappeared. Define
correction/tombstone handling explicitly; unresolved conflicts require review.
Pending records should stay local in the initial upload unless the contract proves
a safe pending-to-posted lifecycle. Balance synchronization requires authoritative
balance/valuation semantics, not summing imported transactions.

On pause/disconnect, discard or freeze queued uploads so they cannot follow a new
server session. Keep independent local records. Explain that disconnecting does
not erase already uploaded server data; remote deletion is a distinct explicit
workflow. Keep the default local and household totals separate even after upload.
A future combined view requires explicit deduplication/account precedence first.

If these requirements are not met by the pinned API, ship **connection** without
claiming Wallet **sync** exists. The free local release must not wait for this
separate backend capability.

## 9. Platform and companion policy

| Platform | First release expectation | Validation |
| --- | --- | --- |
| Eligible iPhone, iOS 26 | Complete automatic Wallet core; Apple model when ready; foreground refresh plus optional background improvement. | Signed physical device, real authorized Wallet, model available/unavailable and offline scenarios. |
| Eligible iPhone, iOS 18–25 | Wallet core and deterministic guided summaries; no Foundation Models requirement. | Deployment guards, fake-backed UI/state tests, representative older runtime/device where available. |
| iPad | Ungated native layout, optional household mode, and honest local-source limitation until import/device sharing exists. | Simulator interaction, keyboard, split view, Dynamic Type and VoiceOver. |
| Mac, macOS 15+ | Same source limitation; current household features; local model guarded at macOS 26. | Mac builds/tests, keyboard navigation, window resizing and accessibility. |
| Watch, watchOS 11+ | Opt-in iPhone-derived snapshot with source and timestamp; no backend required for a local snapshot. | Paired simulator tests plus real-device transfer/removal and stale/offline behavior. |

Use existing WatchConnectivity for the companion snapshot, after a separate
“Show summaries on Apple Watch” choice. Transfer minimal derived content, not a
transaction database. Include schema/source identity and a monotonic revision or
generation so delayed packets cannot restore removed data. Clearing data while
the Watch is offline must be queued and applied when it reconnects; do not claim
instant remote deletion. Inspect Watch persistence/backup behavior as part of
this change.

Do not quietly enable iCloud/CloudKit financial storage to solve the Mac/iPad gap.
A later personal-device sync option can remain independent of Sure, but needs a
separate product decision, explicit disclosure, and a tested identity/deletion
model. The statement-import fallback is the smaller initial expansion.

## 10. Delivery sequence and review boundaries

Each phase should consist of small reviewable changes. No backend mutation is
part of phases 0–5. Phases 6 and 7 can follow independently after the local core.

| Phase | Deliverable and main touch points | Exit gate |
| --- | --- | --- |
| 0. Confirm feasibility/policy | Signed FinanceKit entitlement test; pin the supported device promise; accept source-of-truth/UI scope changes in AGENTS.md and the contract baseline; reconcile SDK documentation. | Authorized iPhone can return real data; distribution provisioning verified. If blocked, do not advertise automatic access. |
| 1. Local data foundation | Domain source IDs/status/coverage; injected FinanceKit boundary; local repository/persistence; replace credit-equals-income mapping; incremental reconciliation. | Deterministic money, pagination/history, crash/restart, removal, pending/posting and currency tests pass. UI still builds throughout. |
| 2. Ungated onboarding and core | `ContentView`, new onboarding feature, independent local finance state, Accounts, Overview and Transactions; move Sure sign-in to optional flow. | Fresh install reaches useful Wallet overview with all app-owned server networking forbidden. Relaunch and revoke/deny recovery work. |
| 3. Device-first Assistant | Context/query services at root, local history persistence, availability-specific UI and guided summaries, explicit destination control. | Local answers use Wallet evidence; no remote call for unavailable/refused models; destination histories cannot leak into each other. |
| 4. Complete feature surfaces | Budget preview, deterministic highlights, source/freshness copy, Settings removal controls; opted-in Watch summaries. Optional local recaps only if justified. | No server-required dead ends in local core; VoiceOver/Dynamic Type/keyboard passes; Watch consent/removal works. |
| 5. Optional household connection | Source selection, per-feature server capabilities, existing-user migration, server-only notification controls and disconnect isolation. | Server errors/logout cannot erase or interrupt local work; existing Sure contract/auth tests stay green. |
| 6. Broader local access | Investigate and implement local Apple Card statement import if universal/platform-independent Card access is a launch requirement. | Verified formats, secure file access, malformed/duplicate import preview, provenance and history-only wording; no fabricated live balance. |
| 7. Optional Wallet upload | Contract spike, precise write-scope policy, consent/mapping/reconciliation spec, then initial import and eventually ongoing updates. | End-to-end idempotency/conflict/readback tests on a controlled self-hosted instance; no silent sharing or duplicate totals. |

Recommended first launch cut: phases 0–5. This is a complete eligible-iPhone
personal finance experience with optional household reading. Do not let an upload
spike postpone local value. If “all Apple Card customers on every app platform”
is a launch promise, phase 6 joins the launch gate rather than being hidden in
marketing. Phase 7 is separately labeled until it is real.

## 11. Acceptance and validation plan

### Behavior and privacy tests

Use Swift Testing, deterministic clocks/IDs, in-memory repositories and synthetic
provider records. Add a failing network spy for never-connected scenarios rather
than relying only on screen copy to establish independence.

- Fresh install → grant Wallet → Overview → local Recent activity → local
  Assistant → restart: zero app-owned backend/remote AI/APNs requests.
- Deny, cancel, zero accounts, no transactions, short history, stale cache,
  unavailable provider, protected data locked, decode failure and revocation each
  render distinct useful states without forcing authentication.
- Sample money case: a posted $100 purchase, $20 refund and $80 card payment
  yields $100 purchases, $20 refunds, $80 net spending, and no inferred income.
  An additional $30 pending authorization is shown separately. Posting it updates
  one transaction instead of counting $60. Add fees, transfers, unknown types,
  negative/zero/large values, JPY/KWD and mixed currencies.
- Test rolling 7/31-day inclusivity, month/year/leap-day boundaries, time zones,
  partial history and equivalent comparison periods. Confirm source-specific
  drill-down rows substantiate summary totals.
- History tests exercise multiple batches, insert/update/delete, invalid token
  recovery, cancelled work, lost writes, restart checkpoints and incomplete
  backfill. Reauthorization must not revive removed records from an old cursor.
- Assistant tests cover model unavailable/not-ready/unsupported language,
  refusal/context exhaustion, cancellation, malicious merchant text, bounded
  tools, typed facts and source/destination switching. Test no local transcript
  or snapshot is attached to a server send.
- Connect, fail authentication, expire session, change host/identity and logout
  while refresh/chat/upload is in flight. Late results cannot cross identities;
  local data and local conversations survive Sure-only lifecycle changes.
- Household budgets/chat/insights each exercise 401, scope 403, feature gating,
  empty results, pagination and independent failures. Connection does not imply
  all optional server features are enabled.
- Watch tests cover sharing off, selected source, stale cache, out-of-order
  messages, permission removal, offline deletion and Sure-only disconnect.
- Future upload tests cover retry after committed-but-lost response, duplicate
  accounts from another provider, partial batch success, server-side edits,
  reinstalls/second devices, read-only credentials, cancellation and revoked
  consent immediately before a send. Remote preflight must obey consent too.

### UI, device and release checks

Build affected targets through Bitrig and run relevant offline tests on iOS and
macOS; build/test Watch for shared snapshot changes. Regenerate from Project.json
after layout/config changes, and update CI path filters/jobs for new directories.
Run the built-in simulator with injected fixtures for every onboarding state,
then use a signed real iPhone for actual FinanceKit authorization and ingestion.
Do not treat the current simulator-unavailable connector as positive coverage.

Check VoiceOver reading order and source/status labels, large Dynamic Type,
contrast, Reduce Motion, touch target sizes, keyboard operation, landscape and
iPad/Mac layouts. Budget previews must be understandable without color, blur or
sample money. Avoid fixed-width suggestion buttons that clip localized content.

Evaluate the model with synthetic datasets on supported real hardware. Confirm
offline local generation after the model is ready; audit app network calls while
exercising the no-server journey. Define a reference device/dataset and record
time to first render, ingestion duration and memory before setting a performance
SLA. Never wait for background history or an AI answer to make navigation usable.

At release, update onboarding screenshots, privacy disclosures and README copy to
match actual data destinations. Do not promise free third-party hosting or
server-side AI: the free guarantee covers the local core. Keep all existing
credential-redaction and Sure contract tests.

## 12. Decisions to review before implementation

These are recommendations, not unanswered prerequisites to finishing this plan.

| Decision | Recommended default | Consequence |
| --- | --- | --- |
| Launch audience | Eligible iPhone Wallet customers first. | Faster complete local release; do not claim universal Apple Card/platform access until a fallback exists. |
| Budget locally | Preview, with a useful route to actual spending. | Avoids inventing a second budgeting system; no local budget editing in this scope. |
| Source aggregation | Separate local and household views. | No silent double counting; a unified total is deferred until deduplication is proven. |
| AI after connection | Keep on-device default; opt into each remote conversation visibly. | Connection cannot silently change data handling or consume server AI. |
| Upload scope | Selected-account one-way copy, then verified ongoing updates. | New financial write exception applies only to the approved import workflow; no Wallet mutations. |
| Personal device continuity | Watch snapshot opt-in now; statement import next; iCloud sync separate. | Initial iPad/Mac local-data limitation is explicit. |
| Local financial/chats backup | Protected storage excluded from backup by default. | Reinstallation may lose local chats and history no longer offered by Wallet; explain this in Settings. |

Unverified dependencies to resolve in their phases: distribution entitlement
approval for `am.sure.insights`; exact eligibility on representative hardware;
usable shared-history coverage metadata; pending/posted replacement behavior;
FinanceKit ID stability across devices/reinstall; statement export formats; and
Sure import/account/balance reconciliation semantics. These are recorded as
validation work, not claims that those capabilities already exist.

Planning validation performed: inspected current entry/composition, all four tab
surfaces, transaction flow, FinanceKit mapping, local AI routing, cache/auth
lifecycle, notification UI, Watch flow and relevant tests; read pinned upstream
contracts and Apple documentation; inspected the installed 26.5 SDK interfaces.
No app code/configuration changed, and no builds or tests ran for this
documentation-only proposal. Runtime behavior and entitlement approval remain
unverified until implementation feasibility checks.

[financekit]: https://developer.apple.com/financekit/
[model]: https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel
[generation]: https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models
[history]: https://developer.apple.com/documentation/financekit/financestore/transactionhistory(foraccountid:since:ismonitoring:)
[sure-clients]: https://github.com/we-promise/sure/blob/5594f8bc94c8e659838cac70d826bbcaeaa3bae2/docs/clients.md
[sure-api]: https://github.com/we-promise/sure/blob/5594f8bc94c8e659838cac70d826bbcaeaa3bae2/docs/api/openapi.yaml
[sure-transactions]: https://github.com/we-promise/sure/blob/5594f8bc94c8e659838cac70d826bbcaeaa3bae2/docs/api/transactions.md
