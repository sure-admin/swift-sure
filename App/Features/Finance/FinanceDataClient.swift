import Foundation

protocol FinanceDataClient {
  func cachedSnapshot() async -> FinanceDataSnapshot?
  func readMetadata(for key: String) async -> ReadMetadata?
  func fetchBalanceSheet() async throws -> BalanceSheetRecord
  func fetchAccounts() async throws -> [FinanceAccount]
  func fetchTransactions(in dateWindow: TransactionDateWindow) async throws -> [FinanceTransaction]
  func fetchBudgetCategories() async throws -> [BudgetCategory]
  func fetchInsights() async throws -> [BackendInsight]
  func acknowledgeInsight(id: UUID, requiredServerURL: URL?) async throws
}

extension FinanceDataClient {
  func acknowledgeInsight(id: UUID) async throws {
    try await acknowledgeInsight(id: id, requiredServerURL: nil)
  }
  func acknowledgeInsight(id: UUID, requiredServerURL: URL?) async throws { throw DataFailure.unavailable }
  func cachedSnapshot() async -> FinanceDataSnapshot? { nil }
  func readMetadata(for key: String) async -> ReadMetadata? { nil }
}
