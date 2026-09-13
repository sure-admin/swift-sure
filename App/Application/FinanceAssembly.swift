import Foundation

@MainActor
struct FinanceAssembly {
  let remoteAssistant: any RemoteAssistantClient
  let financeData: FinanceDataStore
  let appleCardConnection: AppleCardConnectionStore
  let spendingComparison: SpendingComparisonStore
  let transactionHistoryStoreFactory: TransactionHistoryStoreFactory
  let localTransactionHistoryStoreFactory: TransactionHistoryStoreFactory

  init(connection services: ConnectionAssembly, syncInsights: @escaping ([BackendInsight]) -> Void) {
    let connection = services.connection
    let apiClient = services.apiClient
    let transport = services.transport
    let accessGate = services.accessGate
    let lifecycle = services.lifecycle
    let preferences = services.preferences
    let cache = ServerReadCache(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("am.sure.insights/server-reads", isDirectory: true))
    let repository = CachedFinanceRepository(base: apiClient, history: apiClient,
      summaries: FinancialSummaryAPIClient(transport: transport), cache: cache, gate: accessGate,
      identity: { [weak connection] in
        guard let server = connection?.connectedServerURL, let id = connection?.connectedSnapshotIdentity else { return nil }
        return (server, id)
      }, now: { .now },
      legacySnapshotURL: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("am.sure.insights/finance-overview-snapshot.json"),
      legacyResponsesURL: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("am.sure.insights/offline-responses"), remote: apiClient)
    lifecycle.clearOfflineResponses = { try await repository.clear() }
    let financeData = FinanceDataStore(connection: connection, client: repository,
      calendar: .autoupdatingCurrent, now: { .now }, summaries: repository, syncInsights: syncInsights)
    let financeKitConnector = FinanceKitAppleCardConnector(calendar: .autoupdatingCurrent)
    let appleCardConnection = AppleCardConnectionStore(
      connector: financeKitConnector,
      requiresReconnect: preferences.requiresWalletReconnect(),
      setRequiresReconnect: preferences.setRequiresWalletReconnect
    )

    let spendingComparison = SpendingComparisonStore(
      client: repository,
      connection: connection,
      calendar: .autoupdatingCurrent,
      now: { .now },
      walletClient: WalletSpendingComparisonClient(
        transactions: financeKitConnector, calendar: .autoupdatingCurrent, now: { .now }
      ),
      walletAccess: appleCardConnection
    )

    let transactionHistoryStoreFactory = TransactionHistoryStoreFactory(
      client: repository,
      isOffline: { !accessGate.isAllowed },
      calendar: .autoupdatingCurrent,
      now: { .now }
    )
    let localTransactionHistoryStoreFactory = TransactionHistoryStoreFactory(
      client: financeKitConnector,
      calendar: .autoupdatingCurrent,
      now: { .now }
    )
    remoteAssistant = repository
    self.financeData = financeData
    self.appleCardConnection = appleCardConnection
    self.spendingComparison = spendingComparison
    self.transactionHistoryStoreFactory = transactionHistoryStoreFactory
    self.localTransactionHistoryStoreFactory = localTransactionHistoryStoreFactory
  }
}
