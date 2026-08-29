import Foundation

struct SureAPIClient {
  var connection: SureConnection
  private var transport: SureAPITransport
  private var chatPollingPolicy: ChatPollingPolicy

  init(connection: SureConnection) {
    self.connection = connection
    transport = SureAPITransport(connection: connection)
    chatPollingPolicy = .live
  }

  init(
    connection: SureConnection,
    transport: SureAPITransport,
    chatPollingPolicy: ChatPollingPolicy
  ) {
    self.connection = connection
    self.transport = transport
    self.chatPollingPolicy = chatPollingPolicy
  }

  func verifyConnection() async throws {
    try await AccountsAPIClient(transport: transport).verifyAccess()
  }

  func registerPushSubscription(token: String, environment: APNsEnvironment) async throws -> String {
    try await PushSubscriptionsAPIClient(transport: transport)
      .register(token: token, environment: environment)
      .uuidString
      .lowercased()
  }

  func unregisterPushSubscription(id: String) async throws {
    guard let identifier = UUID(uuidString: id) else {
      throw SureAPIError.validation
    }
    try await PushSubscriptionsAPIClient(transport: transport).unregister(id: identifier)
  }

  func createChat() async throws -> String {
    try await ChatsAPIClient(
      transport: transport,
      pollingPolicy: chatPollingPolicy
    )
    .create(title: "Sure for Apple")
    .uuidString
    .lowercased()
  }

  func sendMessage(_ content: String, chatID: String) async throws -> String {
    guard let identifier = UUID(uuidString: chatID) else {
      throw SureAPIError.validation
    }
    return try await ChatsAPIClient(
      transport: transport,
      pollingPolicy: chatPollingPolicy
    )
    .sendMessage(content, chatID: identifier)
  }

  func fetchAccounts() async throws -> [FinanceAccount] {
    try await AccountsAPIClient(transport: transport)
      .fetchAll()
      .map(FinancePresentationMapping.account)
  }

  func fetchTransactions() async throws -> [FinanceTransaction] {
    try await TransactionsAPIClient(transport: transport)
      .fetchAll()
      .map(FinancePresentationMapping.transaction)
      .sorted { $0.date > $1.date }
  }

  func fetchTransactions(_ request: TransactionHistoryRequest) async throws -> [FinanceTransaction] {
    try await TransactionsAPIClient(transport: transport)
      .fetchAll(query: TransactionQuery(historyRequest: request))
      .map(FinancePresentationMapping.transaction)
      .sorted { $0.date > $1.date }
  }

  func fetchBudgetCategories() async throws -> [BudgetCategory] {
    try await LegacyBudgetAPIClient(connection: connection).fetchBudgetCategories()
  }

  func fetchInsights() async throws -> [BackendInsight] {
    try await InsightsAPIClient(transport: transport).fetchInsights()
  }
}

extension SureAPIClient: FinanceDataClient, RemoteAssistantClient, TransactionHistoryClient { }
