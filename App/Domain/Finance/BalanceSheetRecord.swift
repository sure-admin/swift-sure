struct BalanceSheetRecord: Equatable, Sendable {
  var currency: CurrencyCode
  var netWorth: Money
  var assets: Money
  var liabilities: Money
}
