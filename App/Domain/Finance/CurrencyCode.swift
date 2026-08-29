import Foundation

struct CurrencyCode: Hashable, Sendable {
  let rawValue: String

  init?(_ value: String) {
    let normalized = value.uppercased()
    guard normalized.utf8.count == 3,
          normalized.utf8.allSatisfy({ (65...90).contains($0) }),
          Self.isoCurrencies.contains(normalized) else {
      return nil
    }
    rawValue = normalized
  }

  var minorUnitDigits: Int {
    if Self.zeroMinorUnitCurrencies.contains(rawValue) {
      return 0
    }
    if Self.threeMinorUnitCurrencies.contains(rawValue) {
      return 3
    }
    if Self.fourMinorUnitCurrencies.contains(rawValue) {
      return 4
    }
    return 2
  }

  private static let zeroMinorUnitCurrencies: Set<String> = [
    "BIF", "CLP", "DJF", "GNF", "ISK", "JPY", "KMF", "KRW", "PYG",
    "RWF", "UGX", "UYI", "VND", "VUV", "XAF", "XOF", "XPF"
  ]

  private static let threeMinorUnitCurrencies: Set<String> = [
    "BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND"
  ]

  private static let fourMinorUnitCurrencies: Set<String> = ["CLF", "UYW"]

  private static let isoCurrencies = Set(
    Locale.Currency.isoCurrencies.map(\.identifier)
  )
}
