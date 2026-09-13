import Foundation

protocol TransactionHistoryClient {
  func latestDownloadedTransactions(accountID: UUID?) async -> DownloadedTransactionWindow?
  func transactionMetadata(for request: TransactionHistoryRequest) async -> ReadMetadata?
  func fetchTransactions(_ request: TransactionHistoryRequest) async throws -> [FinanceTransaction]
}

extension TransactionHistoryClient {
  func latestDownloadedTransactions(accountID: UUID?) async -> DownloadedTransactionWindow? { nil }
  func transactionMetadata(for request: TransactionHistoryRequest) async -> ReadMetadata? { nil }
}
