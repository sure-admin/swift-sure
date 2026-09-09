import Foundation

struct LocalFinancialBalanceMapper {
  enum Direction {
    case credit
    case debit
  }

  enum MappingError: Error, Equatable {
    case unsupportedCurrency(String)
    case invalidAmount
  }

  func map(
    amount: Decimal,
    currencyCode: String,
    direction: Direction
  ) throws -> Money {
    guard let currency = CurrencyCode(currencyCode) else {
      throw MappingError.unsupportedCurrency(currencyCode)
    }
    let magnitude = amount < 0 ? -amount : amount
    let signedAmount = direction == .credit ? magnitude : -magnitude
    guard let money = Money(decimalValue: signedAmount, currency: currency) else {
      throw MappingError.invalidAmount
    }
    return money
  }
}
