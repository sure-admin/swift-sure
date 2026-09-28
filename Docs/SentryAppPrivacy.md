# Sentry App Privacy disclosure

This worksheet covers the iOS Sentry addition, not the app's existing
authentication, server financial data, assistant, push-notification, or PostHog
disclosures. Preserve those existing disclosures when updating the label.

App Privacy page: https://appstoreconnect.apple.com/apps/6804843427/distribution/privacy

## Status

No DSN is committed. Developers can enable Sentry in local iOS Debug builds
through the ignored `Config/Debug.local.xcconfig`; CI Debug builds keep the
empty default. A release DSN reaches the app only through the
`SURE_SENTRY_DSN` repository secret, which the TestFlight job passes to
`xcodebuild archive`; while that secret is unset the release still builds and
diagnostics is inert. **Complete this worksheet and publish the label before
creating that secret.**

## Implemented collection

Once a DSN is configured, the app sends crash reports, two log records
(`app.launched` and `cleanup.failed`), and a `transactions.load_failed` issue
when transaction history cannot load and no downloaded-data fallback is shown.
The cleanup log has one fixed `operation` attribute. The transaction issue has
only fixed `source` (`sure` or `wallet`), `scope` (`account` or
`recent_activity`), and failure-category tags. No account name or ID, server
URL, request or response, raw error text, financial value, or transaction is
included. Sentry adds an installation-scoped identifier, app/device/OS metadata,
and, for crashes, stack traces and device state at the time of the crash.

Collection is enabled by default. The persistent opt-out is at Sure connection →
Diagnostics → Share diagnostics.

The app does not identify users to Sentry and sends no Sure IDs, server
addresses, credentials, financial content, or conversations. `sendDefaultPii` is
false. Screenshots, view-hierarchy capture, session replay, network tracking,
network breadcrumbs, failed-request capture, automatic breadcrumbs,
user-interaction tracing, performance tracing, release-health session tracking,
watchdog-termination tracking, and app-hang tracking are all disabled.

## Sentry-specific questionnaire entries

Answer that the app collects data. These are additions to, not replacements for,
the existing app-wide label.

| Category → Type | Purpose | Linked to identity | Used for tracking |
| --- | --- | --- | --- |
| Identifiers → Device ID | App Functionality | Yes, via the installation identifier | No |
| Diagnostics → Crash Data | App Functionality | Yes, via that identifier | No |
| Diagnostics → Other Diagnostic Data | App Functionality | Yes, via that identifier | No |

The linkage answer is a conservative application of Apple's definition, which
includes linkage through a device, not just a named account.

Tracking is not enabled by this integration: it does not combine these events
with third-party data for advertising or share them with a data broker.

## Settings to confirm before enabling a DSN

These are project-side settings the SDK options cannot control. Confirm each one
on the Sentry project that the DSN points at, and record the answer here:

- **Data region and hosting.** Which Sentry region or self-hosted instance the
  DSN resolves to, and therefore where diagnostics are processed. An
  international transfer disclosure may be required.
- **IP address storage.** Sentry infers a client IP from the connection unless
  *Prevent Storing of IP Addresses* is enabled in project settings. If IPs are
  retained, add a **Location → Coarse Location** row with an App Functionality
  purpose, as the PostHog worksheet does, and reassess whether the IP is used
  for identification or security.
- **Data retention period** for events on the selected plan.
- **Server-side scrubbing.** Sentry's default PII scrubbing stays on; the client
  options in this repository are the first line, not the only one.

Update the app's published privacy policy at https://sure.am/privacy to name
Sentry alongside PostHog before the first build ships with a DSN.

## Sources

- Apple App Privacy Details: https://developer.apple.com/app-store/app-privacy-details/
- Sentry Apple SDK: https://docs.sentry.io/platforms/apple/guides/ios/
- Sentry Apple SDK options: https://docs.sentry.io/platforms/apple/configuration/options/
- Sentry structured logs: https://docs.sentry.io/platforms/apple/logs/
- SDK 9.29.2 options source: https://github.com/getsentry/sentry-cocoa/blob/9.29.2/Sources/Swift/Options.swift
