import SwiftUI

struct ConnectionSettingsView: View {
  @Environment(\.dismiss) private var dismiss
  var subscriptionAccess: SubscriptionAccessStore
  @Bindable var connection: SureConnection
  var analytics: (any UsageAnalyticsControlling)? = nil

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          SubscriptionAccessView(access: subscriptionAccess)
          if subscriptionAccess.hasAccess {
          Label("Connect to your Sure instance", systemImage: "lock.shield.fill")
            .font(.title2.bold())
          Text("Use a passkey for passwordless sign-in. Face ID or Touch ID confirms it’s you, and your passkey stays in iCloud Keychain.")
            .foregroundStyle(.secondary)

          VStack(alignment: .leading, spacing: 8) {
            Text("Server URL").font(.caption.bold())
            TextField("https://demo.sure.am", text: $connection.serverURL)
              .textFieldStyle(.roundedBorder)
              #if os(iOS)
              .textContentType(.URL)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
              #endif
          }

          Button {
            Task { await connection.signInWithPasskey() }
          } label: {
            HStack {
              if connection.status == .connecting { ProgressView() }
              Text(connection.isOAuthConnected ? "Reconnect with Passkey" : "Continue with Passkey")
              Spacer()
              Image(systemName: "person.badge.key.fill")
            }
            .padding()
            .background(SureTheme.accent, in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(SureTheme.ink)
          }
          .buttonStyle(.plain)
          .disabled(!connection.canSignInWithPasskey || connection.status == .connecting)

          HStack {
            Rectangle().frame(height: 1).foregroundStyle(.quaternary)
            Text("OR USE AN API KEY")
              .font(.caption2.bold())
              .foregroundStyle(.secondary)
            Rectangle().frame(height: 1).foregroundStyle(.quaternary)
          }

          VStack(alignment: .leading, spacing: 8) {
            Text("Create a read/write API key in Sure under Settings → API Key.")
              .font(.caption)
              .foregroundStyle(.secondary)
            Text("API key").font(.caption.bold())
            SecureField("Paste your Sure API key", text: $connection.apiKey)
              .textFieldStyle(.roundedBorder)
              #if os(iOS)
              .textContentType(.password)
              #endif
            if connection.isAPIKeyStored {
              Label("Saved in Keychain", systemImage: "key.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if !connection.apiKey.isEmpty {
              Label("This key couldn’t be saved", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
            }
          }

          Button {
            Task { await connection.connectWithAPIKey() }
          } label: {
            HStack {
              if connection.status == .connecting { ProgressView() }
              Text(connection.isAPIKeyStored ? "Reconnect" : "Save and connect")
              Spacer()
              Image(systemName: "arrow.right")
            }
            .padding()
            .background(SureTheme.accent, in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(SureTheme.ink)
          }
          .buttonStyle(.plain)
          .disabled(!connection.canConnectWithAPIKey || connection.status == .connecting)

          NavigationLink("Password or provider sign-in") {
            SignInView(subscriptionAccess: subscriptionAccess, connection: connection, showConnectionSettings: {})
          }

          statusView
          }

          #if os(iOS)
          if let analytics {
            NavigationLink {
              AnalyticsSettingsView(analytics: analytics)
            } label: {
              Label("Usage analytics", systemImage: "chart.bar.xaxis")
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
          }
          #endif

          if connection.canLogOut {
            Button("Log Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
              Task { await connection.logOut() }
            }
            .buttonStyle(.bordered)
            .disabled(connection.status == .connecting)
            .frame(maxWidth: .infinity, alignment: .center)
          }
        }
        .frame(maxWidth: 560, alignment: .leading)
        .frame(maxWidth: .infinity)
        .padding()
      }
      .navigationTitle("Sure connection")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
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
