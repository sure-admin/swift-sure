# PostHog App Privacy disclosure

This worksheet covers the iOS PostHog addition, not the app's existing authentication,
server financial data, assistant, or push-notification disclosures. Preserve those
existing disclosures when updating the label.

App Privacy page: https://appstoreconnect.apple.com/apps/6804843427/distribution/privacy

## Implemented collection

The app captures `app_opened` and `screen_viewed`. The latter has one app-defined
property, a fixed screen name. PostHog adds an installation-scoped anonymous ID,
session metadata, and standard app/device metadata (including app version, OS,
model, screen dimensions, locale/time zone, and connectivity information).

Collection is enabled by default. The persistent opt-out is at Sure connection →
Usage analytics → Share usage analytics. PostHog uses the US ingestion endpoint.
The app does not identify users to PostHog or send Sure IDs, server addresses,
credentials, financial content, or conversations. Automatic capture, session replay,
crash capture, surveys, and person profiles are disabled.

## PostHog-specific questionnaire entries

Answer that the app collects data. These are additions to, not replacements for,
the existing app-wide label.

| Category → Type | Purpose | Linked to identity | Used for tracking |
| --- | --- | --- | --- |
| Identifiers → Device ID | Analytics | Yes, via the persistent installation identifier | No |
| Usage Data → Product Interaction | Analytics | Yes, via that identifier | No |
| Usage Data → Other Usage Data | Analytics | Yes, via that identifier | No |

The linkage answer is a conservative application of Apple's definition, which
includes linkage through a device, not just a named account. “Anonymous” in the
SDK does not mean the events are identifier-free. PostHog's generic SDK privacy
manifest lists product interaction and other usage data as not linked; the app's
actual use of a persistent installation ID must be assessed separately.

Tracking is not enabled by this integration: it does not combine these events
with third-party data for advertising or share them with a data broker.

### Server-side settings to verify before publishing

The app code cannot establish the PostHog project's IP capture or GeoIP enrichment
settings. Verify them in PostHog. If approximate location is derived and retained,
add Location → Coarse Location, purpose Analytics, linked Yes, tracking No. An IP
address used for a different retained purpose needs classification according to
that actual use; do not infer that IP capture is disabled from SDK anonymity.
No GPS location permission or precise location capture is added by this integration.

## Publishing status and policy

The iOS App Store description was updated through the listing sync to explain
PostHog collection, the US destination, and the opt-out. This does not update the
App Privacy label. The label must be reviewed on the page above and **Publish**
must be clicked; saving a draft is insufficient.

The existing policy at https://sure.am/privacy names PostHog and covers analytics,
device information, and international processing. Confirm that the published
policy also accurately covers this native app's default-on collection and opt-out.

## Sources

- Apple App Privacy Details: https://developer.apple.com/app-store/app-privacy-details/
- PostHog iOS installation: https://posthog.com/docs/libraries/ios
- PostHog IP capture controls: https://posthog.com/docs/privacy/data-collection
- SDK 3.59.3 context: https://github.com/PostHog/posthog-ios/blob/3.59.3/PostHog/PostHogContext.swift
- SDK 3.59.3 manifest: https://github.com/PostHog/posthog-ios/blob/3.59.3/PostHog/Resources/PrivacyInfo.xcprivacy
