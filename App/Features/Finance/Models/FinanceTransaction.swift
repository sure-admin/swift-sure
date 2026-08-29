import Foundation

struct FinanceTransaction: Identifiable {
  var id: UUID
  var merchant: String
  var category: String
  var symbol: String
  var date: LocalDate
  var amount: Money
  var kind: TransactionKind
  var accountID: UUID

  var signedAmount: Money {
    switch kind {
    case .income:
      amount
    case .expense:
      Money(minorUnits: -amount.minorUnits, currency: amount.currency)
    }
  }
}
