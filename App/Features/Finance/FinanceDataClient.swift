protocol FinanceDataClient {
  func fetchAccounts() async throws -> [FinanceAccount]
  func fetchTransactions() async throws -> [FinanceTransaction]
  func fetchBudgetCategories() async throws -> [BudgetCategory]
  func fetchInsights() async throws -> [BackendInsight]
}
