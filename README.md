# Sure for Apple platforms

This repository contains the SwiftUI-native Sure client created with Bitrig. It targets iPhone, iPad, Mac, and Apple Watch from the shared `Project.json` specification.

## Run locally

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen).
2. From the repository root, run `xcodegen generate --spec Project.json`.
3. Open `Sure.xcodeproj` and choose the `Sure` or `Sure Watch` scheme.

The app connects to `https://demo.sure.am` by default. Create a read/write API key under Sure’s **Settings → API Key**, then enter it in **Assistant → Connection Settings**. Credentials are stored in the Apple Keychain and are never committed.

## AI Insight push notifications

The iOS app requests notification permission when the user enables **Notify me about new insights**, registers its APNs token, and uploads the token to Sure through `POST /api/v1/push_subscriptions`. Turning the setting off removes that subscription from Sure.

The Sure deployment must configure these environment variables:

- `APNS_KEY_ID`: the Apple push notification key ID
- `APNS_TEAM_ID`: the Apple Developer team ID
- `APNS_BUNDLE_ID`: `am.sure.insights`
- `APNS_PRIVATE_KEY_BASE64`: the base64-encoded contents of the APNs `.p8` private key

Sure sends sandbox notifications to development and simulator builds and production notifications to TestFlight and App Store builds. Insight delivery also requires Preview Features to be enabled for the Sure user.

## Continuous integration

The repository’s `Bitrig Native` GitHub Actions workflow generates the Xcode project and performs unsigned simulator builds for every supported platform. Push notification delivery requires a paid Apple Developer team and the APNs credentials above.
