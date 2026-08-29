import SwiftUI

struct ConnectionSettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @Bindable var connection: SureConnection
  var financeData: FinanceDataStore

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
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
              Text(connection.isPasskeyConnected ? "Reconnect with Passkey" : "Continue with Passkey")
              Spacer()
              Image(systemName: "person.badge.key.fill")
            }
            .padding()
            .background(SureTheme.accent, in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(SureTheme.ink)
          }
          .buttonStyle(.plain)
          .disabled(URL(string: connection.serverURL) == nil || connection.status == .connecting)

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
              Label("Saved in iCloud Keychain", systemImage: "key.fill")
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

          statusView

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
        connection.isPasskeyConnected ? "Connected securely with Passkey" : "Connected to Sure",
        systemImage: "checkmark.circle.fill"
      )
        .foregroundStyle(.green)
        .task { await financeData.refresh() }
    case .failed(let message):
      Label(message, systemImage: "exclamationmark.triangle.fill")
        .foregroundStyle(.red)
    default:
      Text(connection.status.label)
        .foregroundStyle(.secondary)
    }
  }
}
