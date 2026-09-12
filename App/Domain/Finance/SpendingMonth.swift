import Foundation

struct SpendingMonth: Hashable, Sendable {
  let start: LocalDate

  init(containing date: LocalDate) {
    // Every validated LocalDate's month contains a first day.
    start = try! LocalDate(year: date.year, month: date.month, day: 1)
  }

  var dayCount: Int {
    Self.calendar.range(of: .day, in: .month, for: calendarDate)!.count
  }

  func shifted(by offset: Int) -> SpendingMonth {
    let shifted = Self.calendar.date(byAdding: .month, value: offset, to: calendarDate)!
    return SpendingMonth(containing: try! LocalDate(shifted, in: Self.calendar))
  }

  func date(day: Int) throws -> LocalDate {
    try LocalDate(year: start.year, month: start.month, day: day)
  }

  private var calendarDate: Date {
    Self.calendar.date(from: DateComponents(year: start.year, month: start.month, day: 1))!
  }

  private static var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }
}
