import Foundation

/// What the home screen widget should show after a complete Sure accounts read.
struct AccountsWidgetUpdate: Equatable {
  var accounts: [FinanceAccount]
  /// The server's balance-sheet net worth, when that read has completed.
  var netWorth: DecimalMoney?
  /// When Sure returned the account list (the cached-read timestamp).
  var updatedAt: Date
}
