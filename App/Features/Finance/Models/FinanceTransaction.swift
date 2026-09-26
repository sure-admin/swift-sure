import Foundation

struct FinanceTransaction: Equatable, Identifiable {
  var id: UUID
  var merchant: String
  var category: String
  var symbol: String
  var date: LocalDate
  var amount: Money
  var kind: TransactionKind
  var accountID: UUID
  var merchantCategoryCode: Int16? = nil

  var formattedMerchantCategoryCode: String? {
    // MCCs are identifiers, so preserve four digits without numeric grouping.
    merchantCategoryCode.map { String(format: "%04d", Int($0)) }
  }

  var signedAmount: Money {
    switch kind {
    case .income:
      amount
    case .expense:
      Money(minorUnits: -amount.minorUnits, currency: amount.currency)
    }
  }
}
