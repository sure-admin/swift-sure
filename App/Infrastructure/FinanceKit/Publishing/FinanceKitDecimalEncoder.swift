import Foundation

struct FinanceKitDecimalEncoder: Sendable {
  func money(
    amount: Decimal,
    currency: String,
    direction: FinanceKitSourceMoney.Direction
  ) throws -> FinanceKitSourceMoney {
    guard Self.isCurrencyCode(currency) else { throw FinanceKitSyncError.invalidAmount }
    return FinanceKitSourceMoney(
      amount: try string(amount, maximumIntegerDigits: 15, maximumFractionDigits: 4),
      currency: currency,
      direction: direction
    )
  }

  func exchangeRate(_ value: Decimal) throws -> String {
    try string(value, maximumIntegerDigits: 18, maximumFractionDigits: 18)
  }

  private func string(
    _ value: Decimal,
    maximumIntegerDigits: Int,
    maximumFractionDigits: Int
  ) throws -> String {
    let number = NSDecimalNumber(decimal: value)
    guard number != .notANumber, value >= 0 else { throw FinanceKitSyncError.invalidAmount }
    var copy = value
    let raw = NSDecimalString(&copy, Locale(identifier: "en_US_POSIX"))
    guard !raw.hasPrefix("-"), !raw.contains("e"), !raw.contains("E") else {
      throw FinanceKitSyncError.invalidAmount
    }
    let parts = raw.split(separator: ".", omittingEmptySubsequences: false)
    guard let integer = parts.first,
          (1...maximumIntegerDigits).contains(integer.count),
          integer.allSatisfy({ $0.isASCII && $0.isNumber }),
          parts.count <= 2 else {
      throw FinanceKitSyncError.invalidAmount
    }
    let fraction = parts.count == 2 ? parts[1] : raw[raw.endIndex..<raw.endIndex]
    guard fraction.count <= maximumFractionDigits,
          fraction.allSatisfy({ $0.isASCII && $0.isNumber }) else {
      throw FinanceKitSyncError.invalidAmount
    }
    let trimmedFraction = fraction.reversed().drop(while: { $0 == "0" }).reversed()
    return trimmedFraction.isEmpty ? String(integer) : "\(integer).\(String(trimmedFraction))"
  }

  private static func isCurrencyCode(_ value: String) -> Bool {
    (3...5).contains(value.count) && value.unicodeScalars.allSatisfy { (65...90).contains($0.value) }
  }
}
