import Foundation

enum FinanceFormatters {
  static let currency: FloatingPointFormatStyle<Double>.Currency = .currency(code: "USD").precision(.fractionLength(2))
  static let compactCurrency: FloatingPointFormatStyle<Double>.Currency = .currency(code: "USD").notation(.compactName).precision(.fractionLength(0))
}
