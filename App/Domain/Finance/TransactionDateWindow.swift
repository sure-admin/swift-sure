import Foundation

struct TransactionDateWindow: Equatable, Sendable {
  let startDate: LocalDate
  let endDate: LocalDate

  init(startDate: LocalDate, endDate: LocalDate) throws {
    guard startDate <= endDate else {
      throw TransactionDateWindowError.invalidRange
    }
    self.startDate = startDate
    self.endDate = endDate
  }

  init(inclusiveDayCount: Int, endingAt date: Date, calendar: Calendar) throws {
    guard inclusiveDayCount > 0 else {
      throw TransactionDateWindowError.invalidDayCount
    }

    var gregorianCalendar = Calendar(identifier: .gregorian)
    gregorianCalendar.locale = Locale(identifier: "en_US_POSIX")
    gregorianCalendar.timeZone = calendar.timeZone
    let endOfWindow = gregorianCalendar.startOfDay(for: date)
    guard let startOfWindow = gregorianCalendar.date(
      byAdding: .day,
      value: -(inclusiveDayCount - 1),
      to: endOfWindow
    ) else {
      throw TransactionDateWindowError.calendarCalculationFailed
    }

    try self.init(
      startDate: LocalDate(startOfWindow, in: gregorianCalendar),
      endDate: LocalDate(endOfWindow, in: gregorianCalendar)
    )
  }

  func contains(_ date: LocalDate) -> Bool {
    startDate <= date && date <= endDate
  }
}

private enum TransactionDateWindowError: Error {
  case calendarCalculationFailed
  case invalidDayCount
  case invalidRange
}
