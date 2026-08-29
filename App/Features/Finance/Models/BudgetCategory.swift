import Foundation

struct BudgetCategory: Identifiable {
  var id: UUID
  var name: String
  var symbol: String
  var spent: Money
  var limit: Money

  var progress: Double {
    guard spent.currency == limit.currency,
          limit.decimalValue > 0 else { return 0 }
    return NSDecimalNumber(
      decimal: spent.decimalValue / limit.decimalValue
    ).doubleValue
  }

  var available: Money? {
    limit.subtracting(spent)
  }
}
