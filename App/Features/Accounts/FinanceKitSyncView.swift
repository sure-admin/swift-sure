import SwiftUI

#if os(iOS) && FINANCEKIT_ENABLED
struct FinanceKitSyncView: View {
  @Bindable var sync: FinanceKitSyncStore
  var accounts: [LocalFinancialAccount]
  @State private var consent = false

  var body: some View {
    Form {
      Section("Experimental Finance sync") {
        Text("Send selected Wallet accounts to your Sure family in the background. This device-only preview requires FinanceKit background access and can be turned off at any time.")
        Toggle("I understand this shares financial data with my Sure family", isOn: $consent)
        if case .active = sync.state {
          Label("Sync active", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
          if let last = sync.health?.lastImportedAt { LabeledContent("Last imported", value: last.formatted()) }
          Button("Renew publisher credential") { Task { await sync.renew() } }
        } else if case .repairRequired = sync.state {
          Label("Repair required", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
          Button("Repair Finance sync") { Task { await sync.repair() } }
        } else {
          Button("Enable background sync") { Task { await sync.enroll(accounts: accounts) } }
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
    .navigationTitle("Finance sync")
    .task { await sync.refresh() }
  }
}
#endif
