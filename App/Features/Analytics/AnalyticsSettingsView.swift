import SwiftUI

struct AnalyticsSettingsView: View {
  var analytics: any UsageAnalyticsControlling
  var buildDetails: TelemetryBuildDetails

  var body: some View {
    Form {
      Section {
        Toggle("Share usage analytics", isOn: Binding(
          get: { analytics.isEnabled },
          set: { analytics.setEnabled($0) }
        ))
        .disabled(!analytics.isAvailable)
        .accessibilityHint("Allow Sure to send app usage events to PostHog.")
      } footer: {
        Text("Help improve Sure by sharing which screens you use, along with app and device information, with PostHog. Financial data, server addresses, credentials, and conversations are excluded. No session recordings are collected. You can turn this off at any time.")
      }
      if !analytics.isAvailable {
        Text("Usage analytics is not configured for this build.")
          .foregroundStyle(.secondary)
      }
      #if DEBUG
      Section {
        buildSetting("PostHog project token", value: buildDetails.postHogProjectToken,
          identifier: "posthog-build-token")
        buildSetting("Sentry DSN", value: buildDetails.sentryDSN?.absoluteString,
          identifier: "sentry-build-dsn")
      } header: {
        Text("Debug build configuration")
      } footer: {
        Text("These values are embedded in this build. Sending depends on the Usage analytics and Diagnostics settings.")
      }
      #endif
    }
    .navigationTitle("Usage analytics")
  }

  #if DEBUG
  private func buildSetting(_ title: LocalizedStringKey, value: String?, identifier: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.subheadline)
        .foregroundStyle(.secondary)
      if let value {
        Text(value)
          .font(.footnote.monospaced())
          .textSelection(.enabled)
      } else {
        Text("Not configured")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier(identifier)
  }
  #endif
}

struct TelemetryBuildDetails {
  var postHogProjectToken: String?
  var sentryDSN: URL?
}
