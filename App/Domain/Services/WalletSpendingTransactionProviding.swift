import Foundation

protocol WalletSpendingTransactionProviding: Sendable {
  func fetchSpendingTransactions(in window: TransactionDateWindow, accountIDs: Set<UUID>) async throws -> [WalletSpendingTransaction]
}
