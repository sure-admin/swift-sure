import SwiftUI

struct DiagnosticsSettingsView: View {
  var diagnostics: any DiagnosticsControlling

  var body: some View {
    Form {
      Section {
        Toggle("Share diagnostics", isOn: Binding(
          get: { diagnostics.isEnabled },
          set: { diagnostics.setEnabled($0) }
        ))
        .disabled(!diagnostics.isAvailable)
        .accessibilityHint("Allow Sure to send crash reports and app diagnostics to Sentry.")
      } footer: {
        Text("Help fix crashes by sharing crash reports and a fixed set of app diagnostics with Sentry, along with app and device information. Sure server addresses, credentials, financial data, and conversations are excluded. No screenshots, view recordings, or network addresses are collected. You can turn this off at any time.")
      }
      if !diagnostics.isAvailable {
        Text("Diagnostics is not configured for this build.")
          .foregroundStyle(.secondary)
      }
    }
    .navigationTitle("Diagnostics")
  }
}
