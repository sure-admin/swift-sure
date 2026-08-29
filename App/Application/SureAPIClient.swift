import Foundation

struct SureAPIClient {
  private var transport: SureAPITransport
  private var chatPollingPolicy: ChatPollingPolicy

  init(
    transport: SureAPITransport,
    chatPollingPolicy: ChatPollingPolicy = .live
  ) {
    self.transport = transport
    self.chatPollingPolicy = chatPollingPolicy
  }

  func verifyConnection() async throws {
    try await AccountsAPIClient(transport: transport).verifyAccess()
  }

  func registerPushSubscription(token: String, environment: APNsEnvironment) async throws -> UUID {
    try await PushSubscriptionsAPIClient(transport: transport)
      .register(token: token, environment: environment)
  }

  func unregisterPushSubscription(id: UUID) async throws {
    try await PushSubscriptionsAPIClient(transport: transport).unregister(id: id)
  }

  func createChat() async throws -> UUID {
    try await ChatsAPIClient(
      transport: transport,
      pollingPolicy: chatPollingPolicy
    )
    .create(title: "Sure for Apple")
  }

  func sendMessage(_ content: String, chatID: UUID) async throws -> String {
    try await ChatsAPIClient(
      transport: transport,
      pollingPolicy: chatPollingPolicy
    )
    .sendMessage(content, chatID: chatID)
  }

  func fetchAccounts() async throws -> [FinanceAccount] {
    try await AccountsAPIClient(transport: transport)
      .fetchAll()
      .map(FinancePresentationMapping.account)
  }

  func fetchBalanceSheet() async throws -> BalanceSheetRecord {
    try await BalanceSheetAPIClient(transport: transport).fetch()
  }

  func fetchTransactions(in dateWindow: TransactionDateWindow) async throws -> [FinanceTransaction] {
    try await TransactionsAPIClient(transport: transport)
      .fetchAll(query: TransactionQuery(dateWindow: dateWindow))
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
    try await BudgetsAPIClient(transport: transport)
      .fetchCurrentBudgetCategories()
      .map(BudgetPresentationMapping.category)
  }

  func fetchInsights() async throws -> [BackendInsight] {
    try await InsightsAPIClient(transport: transport).fetchInsights()
  }
}

extension SureAPIClient: FinanceDataClient, RemoteAssistantClient, TransactionHistoryClient { }
