import Foundation

enum FinanceFormatters {
  static func currency(_ money: Money) -> String {
    currency(amount: money.decimalValue, code: money.currency, compact: false)
  }

  static func currency(_ money: DecimalMoney) -> String {
    currency(
      amount: money.amount,
      code: money.currency,
      compact: false,
      locale: .autoupdatingCurrent
    )
  }

  static func currency(_ money: DecimalMoney, locale: Locale) -> String {
    currency(
      amount: money.amount,
      code: money.currency,
      compact: false,
      locale: locale
    )
  }

  static func compactCurrency(_ money: Money) -> String {
    currency(amount: money.decimalValue, code: money.currency, compact: true)
  }

  static func compactCurrency(_ money: DecimalMoney) -> String {
    currency(amount: money.amount, code: money.currency, compact: true)
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

  private static func currency(
    amount: Decimal,
    code: CurrencyCode,
    compact: Bool,
    locale: Locale = .autoupdatingCurrent
  ) -> String {
    let amount = roundedForDisplay(amount, code: code)
    if codeFormattedCurrencies.contains(code.rawValue) {
      return codeFormatted(
        amount: amount,
        code: code,
        compact: compact,
        locale: locale
      )
    }
    if compact {
      return amount.formatted(
        .currency(code: code.rawValue)
          .notation(.compactName)
          .precision(.fractionLength(code.minorUnitDigits))
          .locale(locale)
      )
    }
    return amount.formatted(
      .currency(code: code.rawValue)
        .precision(.fractionLength(code.minorUnitDigits))
        .locale(locale)
    )
  }

  private static func codeFormatted(
    amount value: Decimal,
    code: CurrencyCode,
    compact: Bool,
    locale: Locale
  ) -> String {
    let amount: String
    if compact {
      amount = value.formatted(
        .number
          .notation(.compactName)
          .precision(.fractionLength(code.minorUnitDigits))
          .locale(locale)
      )
    } else {
      amount = value.formatted(
        .number
          .precision(.fractionLength(code.minorUnitDigits))
          .locale(locale)
      )
    }
    return "\(code.rawValue) \(amount)"
  }

  private static func roundedForDisplay(
    _ value: Decimal,
    code: CurrencyCode
  ) -> Decimal {
    var value = value
    var rounded = Decimal.zero
    NSDecimalRound(&rounded, &value, code.minorUnitDigits, .plain)
    return rounded
  }

  private static let codeFormattedCurrencies: Set<String> = [
    "BTC", "DOGE", "GBX", "GGP", "IMP", "JEP", "USDC"
  ]
}
