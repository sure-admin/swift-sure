# Sure Apple Client Repository Guidelines

## Purpose and scope

This repository is the native Apple client for Sure. These instructions apply
to the entire repository unless a more specific `AGENTS.md` exists below a
directory.

Optimize for correctness, privacy, accessibility, and compatibility with
self-hosted Sure instances. Prefer small, reviewable changes over speculative
abstractions. Do not mirror the Rails implementation merely for symmetry; this
client should follow Sure's public contracts and domain language while using
idiomatic Swift and SwiftUI architecture.

## Sources of truth

- `Project.json` is the source of truth for targets, platforms, settings,
  entitlements, generated plists, and source membership. Do not commit a
  generated `.xcodeproj`.
- Sure's generated
  [OpenAPI document](https://github.com/we-promise/sure/blob/main/docs/api/openapi.yaml)
  is the primary server API contract.
- Sure's [client architecture overview](https://github.com/we-promise/sure/blob/main/docs/clients.md),
  [transaction API guide](https://github.com/we-promise/sure/blob/main/docs/api/transactions.md),
  and [chat API guide](https://github.com/we-promise/sure/blob/main/docs/api/chats.md)
  supplement the generated contract where authentication or workflow behavior
  is not fully represented in OpenAPI.
- Sure's [LLM guides](https://github.com/we-promise/sure/tree/main/docs/llm-guides),
  [AI architecture guide](https://github.com/we-promise/sure/blob/main/docs/hosting/ai.md),
  and [upstream repository guidance](https://github.com/we-promise/sure/blob/main/AGENTS.md)
  provide domain and feature context.
- Upstream `main` may be newer than deployed self-hosted instances. When a
  change depends on a newly documented endpoint or field, identify the minimum
  supported Sure version or implement a capability-based fallback. Never infer
  compatibility from the demo server alone.
- Sure is the system of record for financial data. The client may derive
  presentation summaries, but it must not invent server data or reimplement a
  server-owned workflow when a documented API exists.

## Project layout

The current targets are:

- `App/`: sources and assets for the iOS, iPadOS, and macOS app.
- `Watch/`: watchOS-only application sources.
- `Shared/`: the smallest possible set of types compiled into both app targets.
- `appStoreConnect/`: App Store listing metadata, not runtime app code.

Migrate `App/` incrementally toward this feature-oriented layout:

```text
App/
  Application/       App entry points, composition root, platform delegates
  Domain/            UI-independent financial types and rules
  Features/          Overview, Accounts, Budget, Assistant, Transactions
  Infrastructure/    API, authentication, persistence, notifications, devices
  DesignSystem/      Reusable SwiftUI styling and controls
Shared/              Cross-target value types only
Watch/               Watch app UI and watch-specific infrastructure
Tests/SureTests/      Unit and contract tests mirroring production areas
```

Add subfolders only when they clarify ownership. Do not create generic dumping
grounds named `Helpers`, `Managers`, or `Utils`. Do not combine unrelated file
moves with behavior changes; migrate one feature or boundary at a time.

Prefer one primary type per Swift file. Small private supporting types that only
serve that primary type may remain beside it. File names should match their
primary type, and framework type names must not be reused for app types.

## Dependency direction

- `Application` is the composition root. It may construct concrete
  infrastructure and supply it to features.
- Features may depend on domain types and narrow service protocols. They must
  not depend directly on Keychain, `UserDefaults`, `URLSession`, notification
  centers, or WatchConnectivity.
- Infrastructure implements those service protocols. Infrastructure must not
  import feature views.
- Domain code must not import SwiftUI, Security, UserNotifications,
  WatchConnectivity, or other presentation/platform frameworks.
- Feature-to-feature reuse goes through an explicitly shared domain/service
  abstraction, not another feature's view model.
- `Shared/` is for code genuinely required by both app and watch targets; it is
  not a general-purpose common folder.

Use dependency injection at nondeterministic or side-effecting boundaries.
Construct production dependencies at the app root and pass them through
initializers or SwiftUI's environment. Tests must be able to substitute API,
credential, preferences, clock, identifier, notification, and device-sync
implementations.

Do not add new global service singletons. When touching legacy `.shared`,
`URLSession.shared`, `UserDefaults.standard`, or static service access, move the
touched dependency toward an injected boundary when that can be done without a
wide unrelated rewrite. Do not create a protocol for every concrete value type;
protocols are for meaningful seams and alternate implementations.

## API and authentication

- Check the current upstream OpenAPI operation and schema before adding or
  changing an endpoint. Record any intentional compatibility workaround in code
  and cover it with a test fixture.
- Separate transport concerns from endpoint concerns. The transport owns URL
  construction, headers, status validation, decoding, timeouts, and cancellation;
  small domain clients own accounts, transactions, budgets, chats, insights,
  push subscriptions, and authentication operations.
- Use typed `Codable` request/response DTOs that reflect the documented wire
  schema. Map DTOs into domain models explicitly.
- Do not introduce new `[String: Any]` payload parsing, recursive key searches,
  random identifiers for missing required server IDs, or silent `compactMap`
  drops of malformed required records.
- Keep endpoint paths, HTTP methods, query items, headers, and status handling
  strongly typed. Build URLs with `URLComponents`; do not concatenate unescaped
  user input into paths or queries.
- Support both documented request authorization modes behind an injected
  authorizer: OAuth bearer tokens and `X-Api-Key`. Endpoint clients must not
  choose credentials by reading mutable UI state.
- Handle pagination explicitly. Do not treat the first page or the server's
  default page size as a complete collection.
- Distinguish authentication failure, authorization/scope failure, preview
  feature gating, validation failure, transport failure, decoding failure, and
  server failure. In particular, do not collapse every HTTP 403 into “bad
  credentials.”
- API keys and OAuth tokens belong in Keychain and must never be logged, placed
  in `UserDefaults`, committed in fixtures, or exposed in user-facing diagnostics.
- Refresh-token rotation must replace the access and refresh credentials
  atomically, with at most one refresh in flight. Persist a stable per-install
  device identifier when the documented mobile authentication flow requires it.
- Redact authorization headers, credentials, raw authentication payloads, and
  financial/PII response bodies from all diagnostics.
- Treat the configured server as untrusted input. Validate its URL and do not
  weaken TLS behavior silently. Any development-only exception must be explicit
  and unavailable in release builds.
- Preserve cancellation. Do not implement polling with blocking sleeps, and
  bound retry attempts with testable policy.

## Financial-domain correctness

- New monetary domain code must preserve currency and use integer minor units
  or `Decimal`; do not add new financial calculations based on binary
  floating-point `Double`.
- Preserve the server's signed values and classification semantics at the DTO
  boundary. Normalize a sign exactly once in a documented domain mapping.
- Use the server's balance-sheet result for cross-currency net worth. Do not
  recreate authoritative FX conversion from account payloads in the client.
- Centralize date decoding, calendar/time-zone assumptions, and currency
  formatting. Tests must cover month boundaries, negative values, zero, large
  values, and currencies with non-two-decimal minor units when relevant.
- Keep display concerns such as SF Symbols, colors, and localized labels out of
  API DTOs and domain entities. Map them in the feature or design-system layer.
- LLM output is never a source of financial truth. Numbers shown as account,
  transaction, budget, or insight data must originate from typed Sure data or
  be clearly labeled as a local estimate.

## Assistant and privacy boundaries

- Keep on-device Foundation Models responses and Sure server chat as explicit,
  separately testable destinations. UI copy must make the destination and data
  handling understandable.
- Never claim that the local assistant contacted Sure. Never send locally held
  financial context to a remote destination without an explicit user action and
  the intended authenticated route.
- Sure's conversational assistant and background AI pipelines are separate
  upstream systems. Do not infer one system's availability from the other.
- Prefer documented typed endpoints for structured data such as insights. Do
  not scrape prose or prompt the chat assistant to emulate an API when a
  first-class operation is available.

## State, concurrency, and persistence

- Use `@Observable` for app-owned observable models. Put UI-facing mutable
  models on `@MainActor`; keep networking and parsing off the main actor.
- Views render state and send user intents. Networking, persistence, mapping,
  aggregation, and workflow decisions belong outside view bodies.
- Maintain one source of truth for connection and finance state. Avoid hidden
  cross-feature mutation and bidirectional singleton calls.
- Model loading, empty, unavailable, and failure states explicitly. Do not turn
  an unexpected error into an empty collection unless the product deliberately
  defines that degraded behavior and a test covers it.
- Inject time and identifier generation where behavior depends on them. Avoid
  `Date.now` and random UUID fallback inside testable domain workflows.
- Store secrets in Keychain. Store small non-secret preferences in a dedicated
  preferences abstraction. `@AppStorage` is view-only; non-view code reads
  preferences through the injected abstraction or `UserDefaults` adapter.
- Platform delegate callbacks should hand events to an injected application
  service rather than contain feature workflows.

## SwiftUI and platform support

- Support the deployment targets in `Project.json`: iOS 18, macOS 15, and
  watchOS 11. This repository currently builds with the Apple 26.2 SDKs; do not
  use SDK 27 APIs.
- Guard newer platform APIs with the appropriate availability checks and keep
  substantial platform-specific implementations in separate files rather than
  large conditional-compilation blocks.
- Use `NavigationStack`, semantic SwiftUI controls, SF Symbols, Dynamic Type,
  localized user-facing strings, and complete accessibility labels/hints.
- Reuse `DesignSystem` tokens/components before adding hard-coded colors,
  spacing, or duplicate control shapes. Promote a reusable component when a
  second real use appears, not in anticipation of one.
- Use spring-based SwiftUI animation and `sensoryFeedback` where feedback adds
  meaning. Respect Reduce Motion and avoid animation as the only indication of
  state.
- Do not add `PreviewProvider` or `#Preview` declarations in this Bitrig project.
- Keep iPhone, iPad, Mac, and Watch behavior in mind. A successful iPhone build
  alone is not sufficient validation for shared app code.

## Testing

- Use Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`, and
  `#require`) for new unit, domain, state, and API contract tests. Use XCTest
  when required for UI automation or framework interoperability.
- Mirror production ownership under `Tests/SureTests/`, for example
  `Domain/`, `Features/`, and `Infrastructure/API/`. Name files after the type
  or behavior under test.
- A behavior change requires focused tests. A bug fix should add a regression
  test that fails for the original bug whenever practical.
- Tests must be deterministic, parallel-safe, and offline. They must not access
  a live Sure server, real Keychain items, shared user defaults, notification
  permission dialogs, or a physical watch.
- API operations require representative sanitized JSON fixtures for success,
  empty, documented error, and malformed-response paths. Add pagination and
  compatibility fixtures when the operation supports them. Note the upstream
  schema/version that a fixture represents.
- Exercise state transitions and outputs rather than private implementation
  details. Use small hand-written fakes at service boundaries; avoid a broad
  mocking framework unless the standard tools become demonstrably insufficient.
- Do not use arbitrary sleeps. Inject a clock or retry policy and await
  observable completion.
- Coverage is a diagnostic, not a target to game. Prioritize financial math,
  API mapping, auth transitions, persistence boundaries, assistant routing, and
  error recovery before snapshotting simple SwiftUI layout.

## Build and validation

Generate the project after changing `Project.json` or source layout:

```sh
xcodegen generate --spec Project.json
```

Match CI's unsigned builds when validating outside Bitrig:

```sh
xcodebuild -project Sure.xcodeproj -scheme Sure -configuration Debug \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Sure.xcodeproj -scheme Sure -configuration Debug \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Sure.xcodeproj -scheme 'Sure Watch' -configuration Debug \
  -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Once the unit-test target exists, run its generated scheme test action on an
available simulator or macOS destination. A change is not complete when tests
were not run without clearly stating why.

When adding a source directory, target, or test target, update
`.github/workflows/bitrig-native.yml` path filters and jobs. CI must observe
changes under `App/**`, `Shared/**`, `Watch/**`, `Tests/**`, and `Project.json`.

Validate in proportion to the change:

- Domain/API/state change: focused unit tests plus affected app builds.
- Shared type change: app and Watch builds plus relevant tests.
- SwiftUI change: affected platform build and simulator interaction, including
  an accessibility pass.
- Project configuration change: regenerate and build every affected target.

## Change hygiene

- Keep commits small and cohesive. Separate mechanical moves/renames from logic
  changes so behavior remains reviewable.
- Preserve unrelated user changes and avoid broad formatting churn.
- Remove dead sample code, obsolete compatibility paths, and unused model fields
  when their removal is verified; do not leave competing production/sample data
  paths without an explicit purpose.
- Never commit secrets, personal financial data, generated projects, build
  output, local settings, or `.DS_Store` files.
- Comments should explain an invariant, compatibility constraint, privacy
  boundary, or non-obvious tradeoff—not restate the code.
- Update `README.md` and this file when build steps, supported platforms,
  architectural boundaries, or upstream contract policy changes.

## Incremental migration rule

The current code predates several of these boundaries. Apply the rules to new
code immediately and improve touched legacy seams incrementally. Do not launch a
repository-wide rewrite solely to conform to this document. Each migration step
must preserve user-visible behavior, add tests around the seam being changed,
and leave the project buildable.
