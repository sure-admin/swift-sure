import SwiftUI

#if os(iOS) && FINANCEKIT_ENABLED
struct FinanceKitSyncView: View {
  @Bindable var sync: FinanceKitSyncStore
  var accounts: [LocalFinancialAccount]
  @State private var consent = false

  private var isBusy: Bool { sync.state == .syncing || sync.state == .importing }

  var body: some View {
    Form {
      Section("Experimental Wallet sync") {
        Text("Sync selected Wallet accounts to your Sure family. Sure collects and uploads while the app is open; unattended background sync comes later. You can turn this off at any time.")
        Toggle("I understand this shares financial data with my Sure family", isOn: $consent)
        switch sync.state {
        case .active, .syncing, .importing: activeControls
        case .repairRequired:
          Label("Repair required", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
          Button("Repair Wallet sync") { Task { await sync.repair() } }
        default:
          Button("Sync Wallet accounts to your Sure family") { Task { await sync.enroll(accounts: accounts) } }
            .disabled(!consent || accounts.isEmpty)
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
    .task { await sync.refresh() }
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
  }

  private func timestamp(_ label: String, _ value: Date?) -> some View {
    LabeledContent(label, value: value?.formatted() ?? "Not yet")
  }
}
#endif
