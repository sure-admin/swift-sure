import Foundation

struct WalletSpendingComparisonClient: WalletSpendingComparisonProviding {
  var transactions: any WalletSpendingTransactionProviding
  var calendar: Calendar
  var now: @Sendable () -> Date

  func fetchComparison(for month: SpendingMonth, access: WalletSpendingAccess) async throws -> SpendingComparison {
    guard access.isAuthorized, !access.accountIDs.isEmpty else {
      throw WalletSpendingComparisonBuilder.Failure.noAccounts
    }
    let today = try LocalDate(now(), in: calendar)
    let window = try TransactionDateWindow(
      startDate: month.shifted(by: -1).start,
      endDate: min(try month.date(day: month.dayCount), today)
    )
    let entries = try await transactions.fetchSpendingTransactions(in: window, accountIDs: access.accountIDs)
    try Task.checkCancellation()
    return try WalletSpendingComparisonBuilder().build(month: month, asOf: today, access: access, transactions: entries)
  }
}
