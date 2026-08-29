import Foundation

enum FinanceFormatters {
  static func currency(_ money: Money) -> String {
    money.decimalValue.formatted(
      .currency(code: money.currency.rawValue)
    )
  }

  static func compactCurrency(_ money: Money) -> String {
    money.decimalValue.formatted(
      .currency(code: money.currency.rawValue).notation(.compactName)
    )
  }

  static func currency(
    _ breakdown: MoneyBreakdown,
    compact: Bool,
    zeroCurrency: CurrencyCode?
  ) -> String {
    guard breakdown.isAvailable else { return "Unavailable" }
    if breakdown.amounts.isEmpty {
      guard let zeroCurrency else { return "—" }
      let zero = Money(minorUnits: 0, currency: zeroCurrency)
      return compact ? compactCurrency(zero) : currency(zero)
    }
    return breakdown.amounts
      .map { compact ? compactCurrency($0) : currency($0) }
      .joined(separator: " + ")
  }

  static func monthAndDay(_ localDate: LocalDate) -> String {
    displayDate(localDate, calendar: .autoupdatingCurrent)
      .formatted(.dateTime.month(.abbreviated).day())
  }

  static func monthAndYear(_ localDate: LocalDate, calendar: Calendar) -> String {
    let style = Date.FormatStyle(
      calendar: calendar,
      timeZone: calendar.timeZone
    )
      .month(.wide)
      .year()
    return displayDate(localDate, calendar: calendar).formatted(style)
  }

  static func fullDate(_ localDate: LocalDate) -> String {
    displayDate(localDate, calendar: .autoupdatingCurrent)
      .formatted(date: .abbreviated, time: .omitted)
  }

  private static func displayDate(_ localDate: LocalDate, calendar: Calendar) -> Date {
    let calendar = calendar
    var components = DateComponents()
    components.calendar = calendar
    components.timeZone = calendar.timeZone
    components.year = localDate.year
    components.month = localDate.month
    components.day = localDate.day
    components.hour = 12
    return calendar.date(from: components)!
  }
}
