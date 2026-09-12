import Foundation
import Testing
@testable import Sure

@Suite("Spending comparison")
struct SpendingComparisonTests {
  @Test("Current month compares matching days while retaining the full previous curve")
  func matchingDays() throws {
    let value = try fixture(month: 9, day: 11)
    #expect(value.currentTotal == 11)
    #expect(value.previousTotal == 22)
    #expect(value.delta == -11)
    #expect(value.previous.last?.amount == 62)
    #expect(value.previousPlot.count == 30)
    #expect(value.previousPlot.last?.amount == 62)
    #expect(value.previousPlot.last?.date.day == 31)
  }

  @Test("Historical periods compare complete months")
  func historical() throws {
    let value = try fixture(month: 8, day: 11, asOfMonth: 9)
    #expect(value.current.count == 31)
    #expect(value.comparisonDay == 31)
    #expect(value.previousTotal == 62)
  }

  @Test("Calendar boundaries and previous-month cutoff", arguments: [(2028, 3, 31, 29), (2026, 3, 31, 28), (2026, 1, 2, 2)])
  func boundaries(_ input: (Int, Int, Int, Int)) throws {
    let (year, month, day, expectedDay) = input
    let value = try fixture(year: year, month: month, day: day)
    #expect(value.comparisonDay == expectedDay)
    if month == 1 { #expect(value.previous.first?.date.year == year - 1) }
  }

  @Test("Retains zero days and non-two-decimal currencies without rounding", arguments: ["USD", "JPY", "KWD", "BTC"])
  func precision(_ code: String) throws {
    let value = try fixture(month: 9, day: 11, currency: code, currentRate: Decimal(string: "1234567890.00000001")!, previousRate: 0)
    #expect(value.currentTotal == Decimal(string: "13580246790.00000011")!)
    #expect(value.delta == value.currentTotal)
    #expect(value.previous.count == 31)
    #expect(value.previous.allSatisfy { $0.amount == 0 })
  }

  @Test("Empty means both entire series are zero")
  func empty() throws {
    #expect(try fixture(month: 9, day: 11, currentRate: 0, previousRate: 0).isEmpty)
    #expect(try !fixture(month: 9, day: 11, currentRate: 0).isEmpty)
  }

  @Test("Rejects missing, duplicate, decreasing and non-finite series")
  func malformed() throws {
    let value = try fixture(month: 9, day: 11)
    var duplicate = value.current
    duplicate[1].date = duplicate[0].date
    var decreasing = value.current
    decreasing[1].amount = -1
    var notANumber = value.current
    notANumber[1].amount = .nan
    for points in [Array(value.current.dropLast()), duplicate, decreasing, notANumber] {
      #expect(throws: SpendingComparison.ValidationError.self) {
        try SpendingComparison(month: value.month, asOf: value.asOf, currency: value.currency, current: points, previous: value.previous)
      }
    }
  }

  private func fixture(
    year: Int = 2026, month: Int, day: Int, asOfMonth: Int? = nil,
    currency: String = "USD", currentRate: Decimal = 1, previousRate: Decimal = 2
  ) throws -> SpendingComparison {
    let selected = SpendingMonth(containing: try LocalDate(year: year, month: month, day: 1))
    let asOf = try LocalDate(year: year, month: asOfMonth ?? month, day: day)
    let previous = selected.shifted(by: -1)
    func points(_ month: SpendingMonth, days: Int, rate: Decimal) throws -> [SpendingComparison.Point] {
      try (1...days).map { .init(date: try month.date(day: $0), amount: Decimal($0) * rate) }
    }
    return try SpendingComparison(
      month: selected, asOf: asOf, currency: #require(CurrencyCode(currency)),
      current: points(selected, days: asOfMonth == nil ? day : selected.dayCount, rate: currentRate),
      previous: points(previous, days: previous.dayCount, rate: previousRate)
    )
  }
}
