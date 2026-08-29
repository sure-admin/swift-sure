import Foundation

struct APIMoneyDTO: Decodable, Equatable {
  var amount: String
  var currency: String
  var formatted: String

  func money(expectedCurrency: CurrencyCode? = nil) throws -> Money {
    guard amount.range(
      of: #"^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$"#,
      options: .regularExpression
    ) != nil,
    let currencyCode = CurrencyCode(currency),
    expectedCurrency == nil || currencyCode == expectedCurrency,
    let decimal = Decimal(
      string: amount,
      locale: Locale(identifier: "en_US_POSIX")
    ),
    let money = Money(decimalValue: decimal, currency: currencyCode) else {
      throw SureAPIError.decoding
    }
    return money
  }
}
