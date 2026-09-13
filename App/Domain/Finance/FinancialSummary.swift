import Foundation

/// Reporting values are calculated by Sure, including account eligibility and FX.
struct FinancialSummary: Equatable, Sendable {
  var month: SpendingMonth
  var asOf: LocalDate
  var timeZone: String
  var income: DecimalMoney
  var spending: DecimalMoney
  var netSavings: DecimalMoney
  var savingsRate: Decimal?
  var comparison: SpendingComparison
}

protocol FinancialSummaryProviding: Sendable {
  func fetchSummary(for month: SpendingMonth) async throws -> FinancialSummary
}
