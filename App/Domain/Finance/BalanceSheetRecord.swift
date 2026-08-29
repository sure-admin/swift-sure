struct BalanceSheetRecord: Equatable, Sendable {
  var currency: CurrencyCode
  var netWorth: DecimalMoney
  var assets: DecimalMoney
  var liabilities: DecimalMoney
}
