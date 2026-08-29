protocol TransactionHistoryClient {
  func fetchTransactions(_ request: TransactionHistoryRequest) async throws -> [FinanceTransaction]
}
