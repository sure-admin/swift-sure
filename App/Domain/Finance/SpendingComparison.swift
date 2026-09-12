import Foundation

/// Validated, unfurled cumulative series from the explicitly selected spending source.
/// This is deliberately not a wire DTO until an upstream API contract exists.
struct SpendingComparison: Equatable, Sendable {
  let month: SpendingMonth
  let asOf: LocalDate
  let currency: CurrencyCode
  let current: [Point]
  let previous: [Point]

  init(
    month: SpendingMonth,
    asOf: LocalDate,
    currency: CurrencyCode,
    current: [Point],
    previous: [Point]
  ) throws {
    guard month.start <= asOf else { throw ValidationError.invalidPeriod }
    let currentDays = month == SpendingMonth(containing: asOf) ? asOf.day : month.dayCount
    try Self.validate(current, month: month, days: currentDays)
    try Self.validate(previous, month: month.shifted(by: -1), days: month.shifted(by: -1).dayCount)
    self.month = month
    self.asOf = asOf
    self.currency = currency
    self.current = current
    self.previous = previous
  }

  var currentTotal: Decimal { current.last!.amount }
  var comparisonDay: Int {
    month == SpendingMonth(containing: asOf) ? min(current.count, previous.count) : previous.count
  }
  var previousTotal: Decimal { previous[comparisonDay - 1].amount }
  var delta: Decimal { currentTotal - previousTotal }
  var isEmpty: Bool { currentTotal == 0 && previous.last!.amount == 0 }

  /// Preserve the full previous total and actual date when its month is longer.
  /// Header comparison always uses the unfurled series above.
  var previousPlot: [Point] {
    guard previous.count > month.dayCount else { return previous }
    var result = Array(previous.prefix(month.dayCount))
    result[result.count - 1] = previous.last!
    return result
  }

  struct Point: Equatable, Sendable {
    var date: LocalDate
    var amount: Decimal
  }

  enum ValidationError: Error {
    case invalidPeriod
    case incompleteSeries
    case invalidAmount
  }

  private static func validate(_ points: [Point], month: SpendingMonth, days: Int) throws {
    guard points.count == days else { throw ValidationError.incompleteSeries }
    var last = Decimal.zero
    for (index, point) in points.enumerated() {
      guard point.date == (try month.date(day: index + 1)) else {
        throw ValidationError.incompleteSeries
      }
      guard !point.amount.isNaN, point.amount >= last else { throw ValidationError.invalidAmount }
      last = point.amount
    }
  }
}
