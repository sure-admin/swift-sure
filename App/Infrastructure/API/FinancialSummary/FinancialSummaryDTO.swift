import Foundation

struct FinancialSummaryDTO: Codable {
  var month: LocalDate
  var asOf: LocalDate
  var timeZone: String
  var currency: String
  var period: Period
  var income: String
  var spending: String
  var netSavings: String
  var savingsRate: String?
  var spendingComparison: Comparison

  enum CodingKeys: String, CodingKey {
    case month, currency, period, income, spending
    case asOf = "as_of", timeZone = "time_zone", netSavings = "net_savings"
    case savingsRate = "savings_rate", spendingComparison = "spending_comparison"
  }
  struct Period: Codable {
    var startDate: LocalDate
    var endDate: LocalDate
    enum CodingKeys: String, CodingKey { case startDate = "start_date", endDate = "end_date" }
  }
  struct Point: Codable { var date: LocalDate; var amount: String }
  struct Comparison: Codable {
    var previousPeriod: Period
    var currentTotal: String
    var comparisonTotal: String
    var comparisonEndDate: LocalDate
    var delta: String
    var current: [Point]
    var previous: [Point]
    enum CodingKeys: String, CodingKey {
      case current, previous, delta
      case previousPeriod = "previous_period", currentTotal = "current_total"
      case comparisonTotal = "comparison_total", comparisonEndDate = "comparison_end_date"
    }
  }

  func record() throws -> FinancialSummary {
    guard let currency = CurrencyCode(currency), month.day == 1,
          TimeZone(identifier: timeZone) != nil else { throw SureAPIError.decoding }
    let month = SpendingMonth(containing: month)
    let comparison = try SpendingComparison(month: month, asOf: asOf, currency: currency,
      current: spendingComparison.current.map { .init(date: $0.date, amount: try Self.decimal($0.amount)) },
      previous: spendingComparison.previous.map { .init(date: $0.date, amount: try Self.decimal($0.amount)) })
    guard period.startDate == month.start, period.endDate == comparison.current.last?.date,
          spendingComparison.previousPeriod.startDate == month.shifted(by: -1).start,
          spendingComparison.previousPeriod.endDate == comparison.previous.last?.date,
          try Self.decimal(spendingComparison.currentTotal) == comparison.currentTotal,
          try Self.decimal(spendingComparison.comparisonTotal) == comparison.previousTotal,
          try Self.decimal(spendingComparison.delta) == comparison.delta,
          spendingComparison.comparisonEndDate == comparison.previous[comparison.comparisonDay - 1].date else {
      throw SureAPIError.decoding
    }
    return try FinancialSummary(month: month, asOf: asOf, timeZone: timeZone,
      income: .init(amount: Self.decimal(income), currency: currency),
      spending: .init(amount: Self.decimal(spending), currency: currency),
      netSavings: .init(amount: Self.decimal(netSavings), currency: currency),
      savingsRate: savingsRate.map { try Self.decimal($0) / 100 }, comparison: comparison)
  }

  init(_ record: FinancialSummary) {
    let comparison = record.comparison
    month = record.month.start; asOf = record.asOf; timeZone = record.timeZone
    currency = record.income.currency.rawValue
    income = Self.string(record.income.amount); spending = Self.string(record.spending.amount)
    netSavings = Self.string(record.netSavings.amount)
    savingsRate = record.savingsRate.map { Self.string($0 * 100) }
    period = Period(startDate: month, endDate: comparison.current.last!.date)
    spendingComparison = Comparison(
      previousPeriod: Period(startDate: comparison.previous.first!.date, endDate: comparison.previous.last!.date),
      currentTotal: Self.string(comparison.currentTotal), comparisonTotal: Self.string(comparison.previousTotal),
      comparisonEndDate: comparison.previous[comparison.comparisonDay - 1].date, delta: Self.string(comparison.delta),
      current: comparison.current.map { Point(date: $0.date, amount: Self.string($0.amount)) },
      previous: comparison.previous.map { Point(date: $0.date, amount: Self.string($0.amount)) })
  }

  private static func string(_ value: Decimal) -> String { NSDecimalNumber(decimal: value).stringValue }
  private static func decimal(_ string: String) throws -> Decimal {
    let significantDigits = string.filter(\.isNumber).trimmingCharacters(in: CharacterSet(charactersIn: "0"))
    guard significantDigits.count <= 38, string.range(of: #"^-?[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil,
          let value = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")),
          !value.isNaN else { throw SureAPIError.decoding }
    return value
  }
}
