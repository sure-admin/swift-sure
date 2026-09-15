protocol FinanceDataClient {
  func cachedSnapshot() async -> FinanceDataSnapshot?
  func readMetadata(for key: String) async -> ReadMetadata?
  func fetchBalanceSheet() async throws -> BalanceSheetRecord
  func fetchAccounts() async throws -> [FinanceAccount]
  func fetchTransactions(in dateWindow: TransactionDateWindow) async throws -> [FinanceTransaction]
  func fetchBudgetCategories() async throws -> [BudgetCategory]
  func fetchInsights() async throws -> [BackendInsight]
}

extension FinanceDataClient {
  func cachedSnapshot() async -> FinanceDataSnapshot? { nil }
  func readMetadata(for key: String) async -> ReadMetadata? { nil }
}
