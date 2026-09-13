# Sure for Apple platforms

This repository contains the SwiftUI-native Sure client created with Bitrig. It targets iPhone, iPad, Mac, and Apple Watch from the shared `Project.json` specification.

## Run locally

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen).
2. From the repository root, run `xcodegen generate --spec Project.json`.
3. Open `Sure.xcodeproj` and choose the `Sure` or `Sure Watch` scheme.

Production code is organized by ownership: `App/Application` composes the
client, `App/Domain` holds UI-independent values, `App/Features` owns screens
and feature state, `App/Infrastructure` implements external boundaries, and
`App/DesignSystem` contains reusable presentation code. Cross-target value
types live in `Shared`; Watch-owned state and adapters remain in `Watch`.

The default server address is `https://demo.sure.am`; no backend connection or credential entry is allowed until Apple verifies an active trial, paid subscription, or Family Sharing entitlement. In **Connection Settings**, use **Continue with Passkey** to sign in through Sure with Face ID or Touch ID. The app dynamically registers a public OAuth client, uses Authorization Code with PKCE, rotates refresh tokens through a single-flight refresh, and stores the selected server and authorization together in Keychain. A read/write API key remains available as a fallback; its host-bound backup can sync through iCloud Keychain.

## Subscription access

Sure Sync uses Apple StoreKit 2 directly, with no RevenueCat or billing server.
Monthly ($0.99 USD) and yearly ($9.99 USD) plans unlock the same backend features
across devices and servers, with Family Sharing. Both products have a one-week
introductory trial for eligible users. Prices displayed in the app come from
StoreKit and follow the customer's storefront.

The onboarding Wallet preview and on-device Assistant calls are free. Cancelling
renewal preserves access through Apple's entitlement end date; the app warns
when sync will stop. Expiry or revocation blocks authentication, token refresh,
and backend reads/writes, while retained local data stays available. Restoring a
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

Overview uses Sure's authenticated `financial_summary` endpoint for monthly
income, spending, savings rate, and the daily spending comparison. Sure owns
reporting exclusions, account selection, and currency conversion. Overview
fetches only seven days of transaction records for Recent activity.

Before the first successful Sure connection, authorized Wallet accounts can
populate an explicitly labeled local preview. Its posted-debit calculation stays
on-device, excludes transfers, and does not combine currencies. Connected,
offline, suspended, and previously connected sessions use Sure data; logging out
does not restore the onboarding preview. See [spending comparison](Docs/SpendingComparison.md)
and [the read-only architecture](Docs/ReadOnlyArchitecture.md).

## On-device Wallet accounts

During initial onboarding on an iPhone with FinanceKit available, the app opens Accounts without requiring
Sure sign-in. Allow Access loads the eligible accounts shared through Apple
Wallet; selecting an account shows its last 31 days of transactions. Wallet data
stays on the device. All accounts shared by FinanceKit are included, including
supported banks outside Apple’s own products, even when no balance is available.
Accounts refreshes when opened and when the app returns to the foreground.
Eligibility is controlled by Apple and the institution; card activity visible in
Wallet alone does not guarantee that FinanceKit exposes it to apps.

Logging out clears app-held financial data, transaction windows, insights, and
cached conversations. It does not change the original Wallet records or Apple's
system permission. Once Sure has connected successfully, all reporting uses Sure;
future Wallet ingestion must upload source transactions for aggregation on Sure.

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
Mac and Watch do not initialize PostHog.

`Project.json` supplies `SURE_POSTHOG_PROJECT_TOKEN` (a public client ingestion
token, never a personal API key) and `SURE_POSTHOG_HOST`. The current destination
is PostHog US. Self-hosted distributions can replace these build settings with
their own HTTPS ingestion host and project token, or leave either empty to
completely disable initialization. Test hosts do not initialize the SDK.

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
