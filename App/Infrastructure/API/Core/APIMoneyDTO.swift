import Foundation

struct APIMoneyDTO: Decodable, Equatable {
  var amount: String
  var currency: String
  var formatted: String

  func decimalMoney(expectedCurrency: CurrencyCode? = nil) throws -> DecimalMoney {
    guard amount.range(
      of: #"^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$"#,
      options: .regularExpression
    ) != nil,
    let currencyCode = CurrencyCode(currency),
    expectedCurrency == nil || currencyCode == expectedCurrency,
    let decimal = Decimal(
      string: amount,
      locale: Locale(identifier: "en_US_POSIX")
    ) else {
      throw SureAPIError.decoding
    }
    return DecimalMoney(amount: decimal, currency: currencyCode)
  }
}
