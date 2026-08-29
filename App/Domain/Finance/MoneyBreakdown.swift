import Foundation

struct MoneyBreakdown: Equatable, Sendable {
  var amounts: [Money]
  var isAvailable: Bool

  init(aggregating values: [Money]) {
    var totals: [CurrencyCode: Money] = [:]
    for value in values {
      if let current = totals[value.currency] {
        guard let total = current.adding(value) else {
          amounts = []
          isAvailable = false
          return
        }
        totals[value.currency] = total
      } else {
        totals[value.currency] = value
      }
    }
    amounts = totals.values.sorted { $0.currency.rawValue < $1.currency.rawValue }
    isAvailable = true
  }

  var singleAmount: Money? {
    guard isAvailable, amounts.count == 1 else { return nil }
    return amounts[0]
  }
}
