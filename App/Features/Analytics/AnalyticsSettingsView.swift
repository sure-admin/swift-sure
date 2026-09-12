import SwiftUI

struct AnalyticsSettingsView: View {
  var analytics: any UsageAnalyticsControlling

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
    }
    .navigationTitle("Usage analytics")
  }
}
