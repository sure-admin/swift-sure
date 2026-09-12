import Foundation

struct WalletSpendingTransaction: Sendable {
  var id: UUID
  var accountID: UUID
  var date: LocalDate
  var amount: Money
  var isPosted: Bool
  var isDebit: Bool
  var isTransfer: Bool

  var countsAsSpending: Bool { isPosted && isDebit && !isTransfer }
}
