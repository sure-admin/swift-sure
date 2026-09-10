import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, macOS 26.0, *)
struct LocalGetAccountsTool: Tool {
  let name = SureToolInventory.getAccounts.rawValue
  let description = "Get the person's accounts and balances from the synced on-device snapshot. No network access or historical balances."

  var financeData: FinanceDataStore

  @Generable
  struct Arguments {}

  func call(arguments: Arguments) async throws -> String {
    try await AssistantToolRouter(destination: .localSnapshot).call(
      name: name, arguments: [:], localAccounts: snapshot
    )
  }

  private func snapshot() async throws -> String {
    try Task.checkCancellation()
    return try await MainActor.run {
      try Task.checkCancellation()
      // Read current state at invocation so clearing the connection also clears tool access.
      let available = financeData.accountsError == nil
        && (!financeData.accounts.isEmpty || financeData.state == .loaded)
      let result = AccountsResult(
        status: available ? .available : .unavailable,
        accounts: available ? financeData.accounts.map { account in
          Account(
            id: account.id,
            name: account.name,
            balance: NSDecimalNumber(decimal: account.balance.decimalValue).stringValue,
            currency: account.balance.currency.rawValue
          )
        } : []
      )
      return String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
    }
  }

  // Only fields actually present in the local snapshot are exposed. In particular,
  // do not substitute the UI account kind for Sure's classification or account type.
  private struct AccountsResult: Encodable {
    var source = "Synced on-device snapshot; balances may be out of date. Historical balances are unavailable."
    var status: Status
    var accounts: [Account]
  }

  private enum Status: String, Encodable {
    case available
    case unavailable
  }

  private struct Account: Encodable {
    var id: UUID
    var name: String
    var balance: String
    var currency: String
  }
}
#endif
