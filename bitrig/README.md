# Sure for Apple platforms

This directory contains the SwiftUI-native Sure client created with Bitrig. It targets iPhone, iPad, Mac, Apple Watch, and Apple TV from the shared `Project.json` specification.

## Run locally

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen).
2. From this directory, run `xcodegen generate --spec Project.json`.
3. Open `Sure.xcodeproj` and choose the `Sure` or `Sure Watch` scheme.

The app connects to `https://demo.sure.am` by default. Create a read/write API key under Sure’s **Settings → API Key**, then enter it in **Assistant → Connection Settings**. Credentials are stored in the Apple Keychain and are never committed.

## Continuous integration

The repository’s `Bitrig Native` GitHub Actions workflow generates the Xcode project and performs unsigned simulator builds for every supported platform. Push notification delivery still requires an Apple Developer team, a permanent bundle identifier, and an APNs sender configured by the deployment operator.
