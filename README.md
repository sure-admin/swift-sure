# Sure for Apple platforms

This repository contains the SwiftUI-native Sure client created with Bitrig. It targets iPhone, iPad, Mac, and Apple Watch from the shared `Project.json` specification.

The proposed [device-first onboarding plan](Docs/DeviceFirstOnboardingPlan.md)
covers free local Wallet features and optional Sure household connection/upload.
It is a planning document; the runtime behavior described below is unchanged.

## Run locally

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen).
2. From the repository root, run `xcodegen generate --spec Project.json`.
3. Open `Sure.xcodeproj` and choose the `Sure` or `Sure Watch` scheme.

Production code is organized by ownership: `App/Application` composes the
client, `App/Domain` holds UI-independent values, `App/Features` owns screens
and feature state, `App/Infrastructure` implements external boundaries, and
`App/DesignSystem` contains reusable presentation code. Cross-target value
types live in `Shared`; Watch-owned state and adapters remain in `Watch`.

The first-run live demo opens `https://demo.sure.am` without requiring a StoreKit entitlement. Other Sure servers require an active trial, paid subscription, or Family Sharing entitlement before credential entry or backend traffic. In **Connection Settings**, use **Continue with Passkey** to sign in through Sure with Face ID or Touch ID. The app dynamically registers a public OAuth client, uses Authorization Code with PKCE, rotates refresh tokens through a single-flight refresh, and stores the selected server and authorization together in Keychain. A read/write API key remains available as a fallback; its host-bound backup can sync through iCloud Keychain.

## Subscription access

Sure Sync uses Apple StoreKit 2 directly, with no RevenueCat or billing server.
Monthly ($0.99 USD) and yearly ($9.99 USD) plans unlock the same backend features
across devices and servers, with Family Sharing. Both products have a one-week
introductory trial for eligible users. Prices displayed in the app come from
StoreKit and follow the customer's storefront.

The signed-out Wallet preview, public demo, and on-device Assistant calls are free. Cancelling
renewal preserves access through Apple's entitlement end date; the app warns
when sync will stop. Expiry or revocation blocks authentication, token refresh,
and backend reads/writes to other Sure servers. The public demo and retained
local data stay available. Restoring a
subscription re-enables sync without deleting credentials. Previously downloaded
transaction windows are labeled when viewed offline; data never fetched is not
invented. Explicit logout removes the local archives. Hosted app.sure.am
subscription recognition is deferred and does not bypass the authentication gate.

Product definitions are staged under `appStoreConnect/subscriptionGroups/Sure Sync`.
Before testing real purchases, apply the listing and finish the required product
review screenshots. Use a physical device through Bitrig's Run on… or TestFlight
with a Sandbox Apple Account. Unit tests use injected entitlement services;
there is no production bypass and no StoreKit configuration file. See
[the subscription plan and implementation status](Docs/PurchaseAccessPlan.md).

## Spending comparison

Overview uses Sure's authenticated `cash_flow` endpoint for monthly
income, spending, savings rate, and the daily spending comparison. Sure owns
reporting exclusions, account selection, and currency conversion. Overview
fetches only seven days of transaction records for Recent activity.

Before the first successful Sure connection and after explicit logout, authorized Wallet accounts can
populate an explicitly labeled local preview. Its posted-debit calculation stays
on-device, excludes transfers, and does not combine currencies. Connected,
offline, and suspended sessions use Sure data. Logging out restores the Wallet
spending preview without revoking local account access or restoring cached Sure records. See [spending comparison](Docs/SpendingComparison.md)
and [the read-only architecture](Docs/ReadOnlyArchitecture.md).

## First run

A fresh iPhone install with no Sure connection opens a full-screen launch hero
that pitches the on-device Wallet preview and Sure's live demo. Its copy is
parameterized by design variant and region; see [first run](Docs/FirstRun.md)
for the launch arguments that switch them.

## On-device Wallet accounts

Apple Card and Apple Cash accounts and transactions exposed by FinanceKit are
free to use locally. No current or previous subscription, trial, or Sure login
is required, including on a fresh install. A subscription is only required for
Sure backend access.

During initial onboarding or after logout on an iPhone with FinanceKit available, the app opens Accounts without requiring
Sure sign-in. Allow Access loads the eligible accounts shared through Apple
Wallet; selecting an account shows its last 31 days of transactions. Wallet data
stays on the device unless separate Wallet sync consent is granted. Authorized
accounts remain listed alongside Sure accounts, identified by the Apple Wallet
icon and an On Device label, across login, logout, and subscription changes. All accounts shared by FinanceKit are included, including
supported banks outside Apple’s own products, even when no balance is available.
Accounts refreshes when opened and when the app returns to the foreground.
Eligibility is controlled by Apple and the institution; card activity visible in
Wallet alone does not guarantee that FinanceKit exposes it to apps.

Logging out clears downloaded Sure financial data, transaction windows, insights,
and cached conversations, and disconnects the Wallet publisher. Local Wallet
accounts remain accessible while system permission is granted. It does not change the original Wallet records or Apple's
system permission. While connected to Sure, all reporting uses Sure;
future Wallet ingestion must upload source transactions for aggregation on Sure.

The replay-safe publisher core ships in the app behind a foreground trigger: an
explicit **Sync now**, and a debounced sync when the app becomes active. It
cannot upload Wallet data until a revised provider contract is merged into Sure
and pinned here, and the user completes separate upload consent and account
mapping. The iOS 26 background-delivery target is held on a separate branch
until Apple grants its entitlement, so unattended sync is not available. See
[the FinanceKit device publisher architecture](Docs/FinanceKitSyncArchitecture.md).

## AI Insight push notifications

The iOS app requests notification permission when the user enables **Notify urgent insights**, registers its APNs token, and uploads the token to Sure through `POST /api/v1/push_subscriptions`. Turning the setting off removes that subscription from Sure.

The Sure deployment must configure these environment variables:

- `APNS_KEY_ID`: the Apple push notification key ID
- `APNS_TEAM_ID`: the Apple Developer team ID
- `APNS_BUNDLE_ID`: `am.sure.insights`
- `APNS_PRIVATE_KEY_BASE64`: the base64-encoded contents of the APNs `.p8` private key

Sure sends sandbox notifications to development and simulator builds and production notifications to TestFlight and App Store builds. Insight delivery also requires Preview Features to be enabled for the Sure user.

## Tests and continuous integration

The `Sure` scheme runs the offline Swift Testing suite on iOS and macOS. The
`Sure Watch` scheme runs the Watch state suite. The repository’s `Bitrig
Native` workflow generates the Xcode project, runs all three test destinations,
and performs unsigned simulator builds for every supported platform. Push
notification delivery requires a paid Apple Developer team and the APNs
credentials above.

## TestFlight deployments

Pushes to `main` run the complete native CI suite without deploying. Pushing a
tag whose name starts with `v` runs the same tests and platform builds; after
they pass, CI archives the iOS app and uploads it to App Store Connect for
TestFlight processing. CI derives a unique build number above the latest
uploaded build for the current marketing version, so existing manual uploads
and workflow reruns cannot reuse an older number.

Configure these GitHub Actions secrets before merging the deployment workflow:

- `APPLE_DISTRIBUTION_CERTIFICATE_BASE64`: base64-encoded Apple Distribution
  `.p12` certificate and private key
- `APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD`: password for that `.p12`
- `APPLE_TEAM_ID`: Apple Developer team ID
- `APP_STORE_CONNECT_ISSUER_ID`: App Store Connect API issuer ID
- `APP_STORE_CONNECT_KEY_ID`: App Store Connect API key ID
- `APP_STORE_CONNECT_PRIVATE_KEY_BASE64`: base64-encoded App Store Connect API
  `.p8` private key

The API key must be able to manage signing assets and upload builds for bundle
ID `am.sure.insights`. The workflow imports credentials only into an ephemeral
runner keychain and removes them after the deployment job.

## iOS usage analytics

The iPhone/iPad app uses PostHog iOS 3.59.3 for explicit usage events. Analytics
is enabled by default and can be disabled under **Sure connection → Usage
analytics → Share usage analytics**. The preference persists across launches.
The opt-out remains available when Sure sync is subscription-gated. Mac and
Watch do not initialize PostHog.

The project token is not committed. iOS Debug builds can read it from the
Git-ignored `Config/Debug.local.xcconfig`; copy
`Config/Debug.local.example.xcconfig` there and fill in the two local values.
For TestFlight archives made in Bitrig from this checkout, copy
`Config/Release.local.example.xcconfig` to the ignored
`Config/Release.local.xcconfig` and fill in the iOS release values. Bitrig's
Release archive will then embed them; the Debug file alone does not affect it.
The GitHub TestFlight job instead passes the
`SURE_POSTHOG_PROJECT_TOKEN` repository secret to `xcodebuild archive`.
When neither source is present, Release builds default to an empty token.
Pull-request and simulator CI builds have no local file and keep the empty
default.
After a Bitrig upload, install that TestFlight build and open **Sure connection
→ Usage analytics** and **Sure connection → Diagnostics**. Neither screen
should say it is not configured. Release builds do not display the key values.
If either screen does, check that `Config/Release.local.xcconfig` exists in the
same checkout Bitrig archived, then make a new build; changing the file cannot
repair an already uploaded build.

Debug builds show the configured PostHog project token and Sentry DSN on the
**Usage analytics** screen so developers can verify their ingestion destinations.
The build-configuration section is absent from Release builds.

**A missing token is a no-op, not an error.** Analytics reports as unavailable
and the release still builds; the GitHub archive step logs a warning. Use a
public client ingestion token (`phc_…`), never a personal API key.

`SURE_POSTHOG_HOST` stays committed in `Project.json` because the ingestion
endpoint is public infrastructure, not a credential. The current destination is
PostHog US. Self-hosted distributions can point that build setting at their own
HTTPS ingestion host, set their own token secret, or leave the token unset to
disable analytics entirely. Test hosts do not initialize the SDK.

A `phc_` token is a public client key that ships inside the app bundle, so the
secret limits casual scraping of this public repository rather than providing
confidentiality. The token committed before this change remains in git history
and in already-released builds; resetting it under PostHog's **Project settings
→ Danger zone → Reset project API key** is what actually invalidates it, at the
cost of silencing installed builds that still carry the old one.

Events are `app_opened` (one per process launch) and `screen_viewed`, whose only
app-defined property is a fixed `screen` value: `overview`, `assistant`,
`accounts`, `budget`, `connection_settings`, `sign_in`, or `onboarding`.
PostHog also supplies standard app/device/session metadata and an anonymous ID.
No Sure IDs, server addresses, financial values, account/transaction details,
credentials, or conversation text are passed to analytics. The app does not call
`identify`; identity resets after logout and committed connection changes.
Automatic lifecycle/screen/interaction capture, swizzling, session replay,
surveys, and feature-flag preloading are disabled.

Opt-out stops collection and shuts down the SDK. It does not delete events
already received by PostHog or recall requests already in flight. Review the
app's published privacy policy and App Store privacy disclosures for this
collection before distributing a release.

Reference: https://posthog.com/docs/libraries/ios

## iOS diagnostics

The iPhone/iPad app uses the Sentry Cocoa SDK 9.29.2 for crash reports and a
fixed set of app diagnostics. Diagnostics is enabled by default and can be
disabled under **Sure connection → Diagnostics → Share diagnostics**. The
preference persists across launches. Mac and Watch do not initialize Sentry.

The DSN is not committed. The ignored Debug config can provide an iOS
development DSN; its `https:/$()/` spelling prevents xcconfig from treating
the URL's double slash as a comment and expands to `https://` in the app.
Bitrig TestFlight archives can use the ignored `Config/Release.local.xcconfig`
described above. The GitHub TestFlight job instead passes the
`SURE_SENTRY_DSN` repository secret on the `xcodebuild archive` command line.
Release builds without either source default to an empty DSN; pull-request and
simulator CI builds keep that default.

**A missing DSN is a no-op, not an error.** Diagnostics reports as unavailable,
the SDK never initializes, and the release still builds; the GitHub archive
step logs a warning. The same applies to a DSN that is not HTTPS, is missing its
public key, carries the deprecated DSN secret, or carries a query or fragment;
all are rejected. Test hosts never initialize the SDK regardless.

Use the project's public client DSN — never an auth token or an
internal integration key. A DSN is a public client key that ships inside the
app bundle, so keeping it in a repository secret limits casual scraping of this
public repository; it is not confidentiality. If it is ever abused, rotate the
DSN in Sentry and use that project's inbound filters and rate limits. Forks and
self-hosted distributions can set their own `SURE_SENTRY_DSN` secret, pass the
build setting to `xcodebuild` directly, or leave it unset to ship without
diagnostics.

The GitHub TestFlight workflow uploads the Release archive's dSYMs to Sentry before
exporting it to App Store Connect. If `SURE_SENTRY_DSN` is configured, set a
separate `SENTRY_AUTH_TOKEN` repository secret with access to the `chancen` /
`swift-sure` Sentry project and CI symbol-upload permissions. The workflow uses
Sentry's DE endpoint by default. Forks can set the `SENTRY_URL`, `SENTRY_ORG`,
and `SENTRY_PROJECT` repository variables for their own Sentry instance. A
configured DSN without an upload token, or an archive without dSYMs, fails the
release before upload. If the DSN is absent, the symbol step is skipped.

Bitrig TestFlight uploads do not run that GitHub symbol step. Save the matching
archive's dSYMs and upload them separately with `sentry-cli debug-files upload`
using an auth token outside the app build. The DSN alone enables reports but
does not symbolicate crash frames.

For a Debug build on a physical iPhone or iPad, the generated `Sure` scheme has
a post-build symbol-upload action. Install `sentry-cli` locally with
`brew install getsentry/tools/sentry-cli`, then provide an auth token through
`SENTRY_AUTH_TOKEN` in the build environment or an ignored `.sentryclirc` in
the project root. For example, the local file can contain `[auth]` followed by
`token=<your token>` on the next line. It uses the DE endpoint and
`chancen` / `swift-sure` by default; `SENTRY_URL`, `SENTRY_ORG`, and
`SENTRY_PROJECT` environment variables override those for another Sentry
project. The build still runs and sends diagnostics with its configured DSN
when the CLI or upload token is absent, but crash frames may remain
unsymbolicated until the matching dSYM is uploaded. Debug builds that contain
`Sure.debug.dylib` need its matching DWARF image inside `Sure.app.dSYM`; the
post-build action checks for that image before uploading the bundle. Rebuild
and run the app after configuring uploads,
then inspect a new Sentry event to verify its image UUID matches the uploaded
dSYM. A newly built dSYM has a new UUID and cannot symbolicate an event from
an older build; that event needs its original matching dSYM. Keep the auth
token out of the app bundle and the repository.

The app sends crash reports plus two log records: `app.launched` (one per
process launch) and `cleanup.failed`, whose only attribute is a fixed
`operation` value naming the local cleanup step that failed after a Sure session
ended (`offline_responses`, `wallet_publisher_disconnect`,
`wallet_background_delivery`, or `app_data_reset`). When a transaction history
load reaches the “Couldn’t load transactions” state, the app also captures a
`transactions.load_failed` Sentry issue. Its tags and grouping fingerprint
contain only fixed source (`sure` or `wallet`), scope (`account` or
`recent_activity`), and failure category values. A cancelled request or one
recovered with downloaded transactions does not create an issue. Failed budget
reads create a `budgets.load_failed` issue with a fixed failure category and
whether downloaded data remains available. Wallet sync failures create a
`wallet.sync_failed` issue with fixed operation and failure categories; rejected
batches may also include a known protocol rejection, validation field, and
validation rule. Pending imports, lock contention, and cancelled work are not
reported as failures. Sentry also
supplies app, device, and OS metadata and an installation-scoped identifier.

Every automatic collector is off, because Sentry's defaults would otherwise
capture the data this app must not send. Network tracking, network breadcrumbs
and failed-request capture would record self-hosted Sure server addresses;
screenshots, view-hierarchy capture and session replay would record account
balances; swizzling, automatic breadcrumbs, user-interaction tracing and
performance tracing are unnecessary for this vocabulary. Release-health session
tracking, watchdog-termination tracking and app-hang tracking are also off, and
`sendDefaultPii` is false. A `beforeSendLog` hook drops any log outside the two
messages above, and `beforeSend` clears the user, request, breadcrumb and
server-name fields from issue events, including crashes.

No Sure IDs, server addresses, financial values, account or transaction details,
credentials, or conversation text are passed to diagnostics. Opt-out stops
collection, flushes what is queued, and uninstalls the crash handler. It does not
delete events already received by Sentry. Review the app's published privacy
policy and App Store privacy disclosures for this collection before distributing
a release, and see `Docs/SentryAppPrivacy.md`.

Reference: https://docs.sentry.io/platforms/apple/guides/ios/

## Consolidation validation

`swiftlint lint --strict --quiet` checks the configured correctness rules.
The `Sure UI Host` scheme runs production views with in-memory fixtures in a
separate app, including onboarding/connected source boundaries, retry behavior,
and accessibility descriptions. It never constructs production services.

```sh
xcodegen generate --spec Project.json
xcodebuild -project Sure.xcodeproj -scheme 'Sure UI Host' -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO test
```

Continue to run the main Sure suites on iOS and macOS, and the Sure Watch suite
on a paired simulator for Watch changes. Generated projects and Info.plists
remain untracked.

For the experimental foreground Wallet publisher, see the
[FinanceKit device-test checklist](Docs/FinanceKitDeviceTesting.md).
