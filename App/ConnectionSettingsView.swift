import SwiftUI

struct ConnectionSettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var connection = SureConnection.shared

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          Label("Connect to your Sure instance", systemImage: "lock.shield.fill")
            .font(.title2.bold())
          Text("Create a read/write API key in Sure under Settings → API Key. It is stored only in this device’s Keychain.")
            .foregroundStyle(.secondary)

          VStack(alignment: .leading, spacing: 8) {
            Text("Server URL").font(.caption.bold())
            TextField("https://demo.sure.am", text: $connection.serverURL)
              .textContentType(.URL)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
              .textFieldStyle(.roundedBorder)
            Text("API key").font(.caption.bold())
            SecureField("Paste your Sure API key", text: $connection.apiKey)
              .textContentType(.password)
              .textFieldStyle(.roundedBorder)
            if connection.isAPIKeyStored {
              Label("Saved in this device’s Keychain", systemImage: "key.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if !connection.apiKey.isEmpty {
              Label("This key couldn’t be saved", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
            }
          }

          Button {
            Task { await connection.test() }
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
          .disabled(!connection.isConfigured || connection.status == .connecting)

          statusView
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
      Label("Connected to Sure", systemImage: "checkmark.circle.fill")
        .foregroundStyle(.green)
        .task { await FinanceDataStore.shared.refresh() }
    case .failed(let message):
      Label(message, systemImage: "exclamationmark.triangle.fill")
        .foregroundStyle(.red)
    default:
      Text(connection.status.label)
        .foregroundStyle(.secondary)
    }
  }
}
