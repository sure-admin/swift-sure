import Foundation

/// Reopens the last fully fetched window for a scope when connectivity is locked.
/// Partial pages are never published as a complete offline transaction window.
@MainActor
struct ArchivedTransactionHistoryClient: TransactionHistoryClient {
  var base: any TransactionHistoryClient
  var gate: BackendAccessGate
  var archive: OfflineAPIResponseStore
  var identity: () -> (URL, String)?
  var now: () -> Date

  func fetchTransactions(_ request: TransactionHistoryRequest) async throws -> [FinanceTransaction] {
    guard let (server, identity) = identity() else { throw BackendAccessError.subscriptionRequired }
    let scope = request.accountID?.uuidString ?? "all"
    let key = "transactions\n" + server.absoluteString + "\n" + identity + "\n" + scope
    let codec = FinanceDataSnapshotCodec()
    if !gate.isAllowed {
      guard let data = try await archive.read(key: key) else { throw BackendAccessError.subscriptionRequired }
      let saved = try codec.decode(data)
      guard saved.serverURL == server, saved.connectionIdentity == identity,
            self.identity()?.1 == identity else { throw CancellationError() }
      return saved.transactions
    }
    let permit = try gate.permit()
    let transactions = try await base.fetchTransactions(request)
    try gate.validate(permit)
    guard self.identity()?.1 == identity else { throw CancellationError() }
    let snapshot = FinanceDataSnapshot(serverURL: server, connectionIdentity: identity,
      balanceSheet: nil, accounts: [], transactions: transactions, budgets: [], insights: [], lastUpdated: now())
    try await archive.write(codec.encode(snapshot), key: key)
    return transactions
  }
}
