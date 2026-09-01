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

  func fetchConversations() async throws -> [AssistantConversation] {
    try await ChatsAPIClient(
      transport: transport,
      pollingPolicy: chatPollingPolicy
    )
    .fetchAll()
    .map {
      AssistantConversation(id: $0.id, title: $0.title, updatedAt: $0.updatedAt)
    }
  }

  func fetchConversation(id: UUID) async throws -> AssistantConversationDetail {
    let response = try await ChatsAPIClient(
      transport: transport,
      pollingPolicy: chatPollingPolicy
    )
    .fetch(id: id)
    return AssistantConversationDetail(
      conversation: AssistantConversation(
        id: response.id,
        title: response.title,
        updatedAt: response.updatedAt
      ),
      messages: response.messages.map {
        AssistantMessage(
          id: $0.id,
          role: $0.role == .user ? .user : .assistant,
          content: $0.content,
          date: $0.createdAt
        )
      }
    )
  }

  func createChat(title: String) async throws -> UUID {
    try await ChatsAPIClient(
      transport: transport,
      pollingPolicy: chatPollingPolicy
    )
    .create(title: title)
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
