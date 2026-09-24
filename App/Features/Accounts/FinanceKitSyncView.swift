import SwiftUI

#if os(iOS) && FINANCEKIT_ENABLED
struct FinanceKitSyncView: View {
  @Bindable var sync: FinanceKitSyncStore
  var wallet: AppleCardConnectionStore

  private var isBusy: Bool { sync.isBusy || sync.state == .importing }

  var body: some View {
    Form {
      Section("Experimental Wallet sync") {
        Text("Sync selected Wallet accounts to your Sure family. Sure collects and uploads while the app is open; unattended background sync comes later. You can turn this off at any time.")
        Toggle("I understand this shares financial data with my Sure family", isOn: Binding(
          get: { sync.consentAcknowledged }, set: { sync.requestConsentChange($0) }))
          .disabled(sync.isBusy || sync.needsDisconnectRetry)
        if sync.needsDisconnectRetry {
          Button("Retry disconnect") { Task { await sync.stopKeepingHistory() } }
            .disabled(sync.isBusy)
        } else {
          switch sync.state {
          case .active, .syncing, .importing: activeControls
          case .enrolling:
            ProgressView("Enabling Wallet sync…")
              .accessibilityIdentifier("wallet-sync-enrollment-progress")
          case .repairRequired:
            Label("Repair required", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            if let message = sync.rejectionMessage {
              Text(message)
                .accessibilityIdentifier("wallet-sync-batch-rejection")
                .textSelection(.enabled)
            }
            Button("Repair Wallet sync") { Task { await sync.repair() } }
              .disabled(sync.isBusy)
          default:
            Button("Sync Wallet accounts to your Sure family") { Task { await sync.enroll(accounts: wallet.accounts) } }
              .disabled(!sync.consentAcknowledged || sync.isBusy || wallet.accounts.isEmpty || wallet.state != .authorized)
          }
        }
        ForEach(sync.conflicts) { conflict in
          VStack(alignment: .leading) {
            Text(conflict.kind.replacingOccurrences(of: "_", with: " ")).font(.headline)
            HStack {
              Button("Keep Sure version") { Task { await sync.resolve(conflict, keepingSure: true) } }
              Button("Repair from Wallet") { Task { await sync.resolve(conflict, keepingSure: false) } }
            }
          }
        }
        if case .failed(let message) = sync.state { Text(message).foregroundStyle(.red) }
      }
    }
    .navigationTitle("Wallet sync")
    .alert("Stop Wallet sync?", isPresented: $sync.showsConsentWithdrawalConfirmation) {
      Button("Keep synchronized transactions") { Task { await sync.stopKeepingHistory() } }
      Button("Cancel", role: .cancel) { }
    } message: {
      Text("Stop sending Wallet data to Sure? Previously synchronized transactions can stay on the server. Deleting synchronized transactions isn’t available from this app yet.")
    }
    .task {
      await wallet.refresh()
      await sync.refresh()
    }
  }

  @ViewBuilder private var activeControls: some View {
    switch sync.state {
    case .syncing:
      Label("Sending Wallet changes…", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.secondary)
    case .importing:
      Label("Sure has your changes and is still importing them.", systemImage: "clock.arrow.circlepath")
        .foregroundStyle(.secondary)
    default:
      Label("Sync active", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
    }
    Button { Task { await sync.sync() } } label: {
      HStack {
        Text("Sync now")
        if isBusy {
          Spacer()
          ProgressView()
        }
      }
    }
    .disabled(isBusy)
    // Accepted and imported are separate facts on the server. Collapsing them
    // into one "last synced" would claim a freshness Sure cannot vouch for.
    timestamp("Last accepted by Sure", sync.health?.lastAcceptedAt)
    timestamp("Last imported into your family", sync.health?.lastImportedAt)
    Button("Renew publisher credential") { Task { await sync.renew() } }
      .disabled(sync.isBusy)
  }

  private func timestamp(_ label: String, _ value: Date?) -> some View {
    LabeledContent(label, value: value?.formatted() ?? "Not yet")
  }
}
#endif
