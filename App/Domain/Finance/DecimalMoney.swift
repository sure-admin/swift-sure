import Foundation

struct DecimalMoney: Equatable, Sendable {
  var amount: Decimal
  var currency: CurrencyCode
}
