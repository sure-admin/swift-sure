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

The app connects to `https://demo.sure.am` by default. In **Connection Settings**, use **Continue with Passkey** to sign in through Sure with Face ID or Touch ID. The app dynamically registers a public OAuth client, uses Authorization Code with PKCE, rotates refresh tokens through a single-flight refresh, and stores the selected server and authorization together in Keychain. A read/write API key remains available as a fallback; its host-bound backup can sync through iCloud Keychain.

## Local assistant account tool

On an Apple Intelligence device running iOS 26 or macOS 26, select the local
assistant and ask “What accounts do I have, and what are their balances?”
The Foundation Models session has a no-argument `get_accounts` tool that reads
the current synced on-device snapshot. Account records are supplied through
the tool instead of being embedded in every prompt. The tool makes no network
requests and returns account IDs, names, exact decimal balances, and currencies.
It distinguishes unavailable data from an empty loaded collection; balances
may be out of date. Historical balances and provider details are not included.

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

Assistant tool inventory regeneration, mobile availability policy, and the
explicit MCP delegation boundary are documented in
[Assistant tool delegation](Docs/AssistantToolDelegation.md).
