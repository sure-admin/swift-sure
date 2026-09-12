import Foundation

struct WalletSpendingComparisonBuilder {
  func build(
    month: SpendingMonth, asOf: LocalDate, access: WalletSpendingAccess,
    transactions: [WalletSpendingTransaction]
  ) throws -> SpendingComparison {
    guard access.isAuthorized, !access.accountIDs.isEmpty else { throw Failure.noAccounts }
    let previous = month.shifted(by: -1)
    let currentEnd = min(try month.date(day: month.dayCount), asOf)
    let window = try TransactionDateWindow(startDate: previous.start, endDate: currentEnd)
    let expenses = transactions.filter {
      access.accountIDs.contains($0.accountID) && window.contains($0.date) && $0.countsAsSpending
    }
    guard Set(expenses.map(\.id)).count == expenses.count else { throw Failure.invalidData }
    let currencies = Set(expenses.map { $0.amount.currency }).union(access.currencies)
    guard currencies.count <= 1 else { throw Failure.multipleCurrencies }
    guard let currency = currencies.first else { throw Failure.unknownCurrency }
    var daily: [LocalDate: Decimal] = [:]
    for expense in expenses {
      guard expense.amount.minorUnits >= 0 else { throw Failure.invalidData }
      daily[expense.date, default: 0] += expense.amount.decimalValue
    }
    func series(_ month: SpendingMonth, days: Int) throws -> [SpendingComparison.Point] {
      var total = Decimal.zero
      return try (1...days).map { day in
        let date = try month.date(day: day)
        total += daily[date, default: 0]
        return .init(date: date, amount: total)
      }
    }
    return try SpendingComparison(
      month: month, asOf: asOf, currency: currency,
      current: series(month, days: currentEnd.day),
      previous: series(previous, days: previous.dayCount)
    )
  }

  enum Failure: Error {
    case noAccounts, multipleCurrencies, unknownCurrency, invalidData
  }
}
