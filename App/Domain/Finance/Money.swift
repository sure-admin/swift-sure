import Foundation

struct Money: Equatable, Sendable {
  var minorUnits: Int64
  var currency: CurrencyCode

  var decimalValue: Decimal {
    var divisor = Decimal(1)
    for _ in 0..<currency.minorUnitDigits {
      divisor *= 10
    }
    return Decimal(minorUnits) / divisor
  }

  // Temporary presentation bridge for legacy views that still format Double.
  var legacyDoubleValue: Double {
    NSDecimalNumber(decimal: decimalValue).doubleValue
  }
}
