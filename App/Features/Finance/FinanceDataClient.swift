protocol FinanceDataClient {
  func fetchBalanceSheet() async throws -> BalanceSheetRecord
  func fetchAccounts() async throws -> [FinanceAccount]
  func fetchTransactions(in dateWindow: TransactionDateWindow) async throws -> [FinanceTransaction]
  func fetchBudgetCategories() async throws -> [BudgetCategory]
  func fetchInsights() async throws -> [BackendInsight]
}
