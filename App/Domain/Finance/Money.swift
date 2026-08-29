import Foundation

struct Money: Equatable, Hashable, Sendable {
  var minorUnits: Int64
  var currency: CurrencyCode

  init(minorUnits: Int64, currency: CurrencyCode) {
    self.minorUnits = minorUnits
    self.currency = currency
  }

  init?(decimalValue: Decimal, currency: CurrencyCode) {
    var scaledValue = decimalValue * Self.divisor(for: currency)
    var integralValue = Decimal()
    NSDecimalRound(&integralValue, &scaledValue, 0, .plain)
    guard integralValue == scaledValue else { return nil }

    let number = NSDecimalNumber(decimal: integralValue)
    let minorUnits = number.int64Value
    guard number != .notANumber,
          Decimal(minorUnits) == integralValue else {
      return nil
    }
    self.init(minorUnits: minorUnits, currency: currency)
  }

  var decimalValue: Decimal {
    Decimal(minorUnits) / Self.divisor(for: currency)
  }

  var magnitude: Money? {
    guard minorUnits != Int64.min else { return nil }
    return Money(minorUnits: Swift.abs(minorUnits), currency: currency)
  }

  func adding(_ other: Money) -> Money? {
    guard currency == other.currency else { return nil }
    let result = minorUnits.addingReportingOverflow(other.minorUnits)
    guard !result.overflow else { return nil }
    return Money(minorUnits: result.partialValue, currency: currency)
  }

  func subtracting(_ other: Money) -> Money? {
    guard currency == other.currency else { return nil }
    let result = minorUnits.subtractingReportingOverflow(other.minorUnits)
    guard !result.overflow else { return nil }
    return Money(minorUnits: result.partialValue, currency: currency)
  }

  private static func divisor(for currency: CurrencyCode) -> Decimal {
    Decimal(currency.minorUnitConversion)
  }
}
