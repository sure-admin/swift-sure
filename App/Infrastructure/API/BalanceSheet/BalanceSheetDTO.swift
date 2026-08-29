struct BalanceSheetDTO: Decodable, Equatable {
  var currency: String
  var netWorth: APIMoneyDTO
  var assets: APIMoneyDTO
  var liabilities: APIMoneyDTO

  enum CodingKeys: String, CodingKey {
    case currency
    case netWorth = "net_worth"
    case assets
    case liabilities
  }

  func record() throws -> BalanceSheetRecord {
    guard let currencyCode = CurrencyCode(currency) else {
      throw SureAPIError.decoding
    }
    return BalanceSheetRecord(
      currency: currencyCode,
      netWorth: try netWorth.decimalMoney(expectedCurrency: currencyCode),
      assets: try assets.decimalMoney(expectedCurrency: currencyCode),
      liabilities: try liabilities.decimalMoney(expectedCurrency: currencyCode)
    )
  }
}
