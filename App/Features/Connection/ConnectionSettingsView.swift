import SwiftUI

struct ConnectionSettingsView: View {
  @Environment(\.dismiss) private var dismiss
  var subscriptionAccess: SubscriptionAccessStore
  @Bindable var connection: SureConnection
  var analytics: (any UsageAnalyticsControlling)? = nil
  var telemetryBuildDetails = TelemetryBuildDetails(postHogProjectToken: nil, sentryDSN: nil)
  var diagnostics: (any DiagnosticsControlling)? = nil
  var financeKitSync: FinanceKitSyncStore? = nil
  var wallet: AppleCardConnectionStore? = nil

  var body: some View {
    NavigationStack {
      Form {
        Section("Connection") {
          serverField
          statusView
        }

        Section("Subscription") {
          NavigationLink(subscriptionAccess.hasAccess ? "Manage subscription" : "View subscription plans") {
            SubscriptionAccessView(access: subscriptionAccess)
              .navigationTitle("Subscription")
          }
        }

        walletSection
        privacySection

        Section("Advanced") {
          DisclosureGroup("API key access") {
            if allowsCredentialEntry {
              apiKeyControls
            } else {
              Text("Start or restore a subscription before connecting with an API key. The public demo remains free.")
                .foregroundStyle(.secondary)
            }
          }
        }

        if connection.canLogOut {
          Section {
            Button("Log Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
              Task { await connection.logOut() }
            }
            .disabled(connection.status == .connecting)
          }
        }
      }
      .formStyle(.grouped)
      .navigationTitle("Settings")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
  }

  private var allowsCredentialEntry: Bool { subscriptionAccess.hasAccess || connection.isDemoServer }

  private var serverField: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Server URL").font(.caption.bold())
      TextField("Server URL", text: $connection.serverURL, prompt: Text("https://sure.example.com"))
        .accessibilityLabel("Server URL")
        .accessibilityIdentifier("settings-server-url")
        #if os(iOS)
        .keyboardType(.URL)
        .textContentType(.URL)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        #endif
    }
  }

  @ViewBuilder
  private var apiKeyControls: some View {
    Text("Create a read/write API key in Sure under Settings → API Key.")
      .font(.caption)
      .foregroundStyle(.secondary)
    SecureField("Paste your Sure API key", text: $connection.apiKey)
      .accessibilityLabel("API key")
      .accessibilityIdentifier("settings-api-key")
      #if os(iOS)
      .textContentType(.password)
      #endif
    if connection.isAPIKeyStored {
      Label("Saved in Keychain", systemImage: "key.fill")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    Button(connection.isAPIKeyStored ? "Reconnect" : "Save and connect") {
      Task { await connection.connectWithAPIKey() }
    }
    .disabled(!connection.canConnectWithAPIKey || connection.status == .connecting)
  }

  @ViewBuilder
  private var walletSection: some View {
    #if os(iOS) && FINANCEKIT_ENABLED
    if let financeKitSync, let wallet {
      Section("Wallet") {
        NavigationLink {
          FinanceKitSyncView(sync: financeKitSync, wallet: wallet)
        } label: {
          Label("Experimental Wallet sync", systemImage: "arrow.triangle.2.circlepath")
        }
      }
    }
    #endif
  }

  @ViewBuilder
  private var privacySection: some View {
    #if os(iOS)
    if analytics != nil || diagnostics != nil {
      Section("Privacy") {
        analyticsLink
        diagnosticsLink
      }
    }
    #endif
  }

  @ViewBuilder
  private var analyticsLink: some View {
    #if os(iOS)
    if let analytics {
      NavigationLink {
        AnalyticsSettingsView(analytics: analytics, buildDetails: telemetryBuildDetails)
      } label: {
        Label("Usage analytics", systemImage: "chart.bar.xaxis")
          .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
          .contentShape(Rectangle())
      }
    }
    #endif
  }

  @ViewBuilder
  private var diagnosticsLink: some View {
    #if os(iOS)
    if let diagnostics {
      NavigationLink {
        DiagnosticsSettingsView(diagnostics: diagnostics)
      } label: {
        Label("Diagnostics", systemImage: "ladybug")
          .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
          .contentShape(Rectangle())
      }
    }
    #endif
  }

  @ViewBuilder
  private var statusView: some View {
    switch connection.status {
    case .connected:
      Label(
        connection.isOAuthConnected ? "Connected securely" : "Connected to Sure",
        systemImage: "checkmark.circle.fill"
      )
        .foregroundStyle(.green)
    case .failed(let message):
      Label(message, systemImage: "exclamationmark.triangle.fill")
        .foregroundStyle(.red)
    default:
      Text(connection.status.label)
        .foregroundStyle(.secondary)
    }
  }
}
