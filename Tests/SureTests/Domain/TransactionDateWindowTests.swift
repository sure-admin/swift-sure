import Foundation
import Testing
@testable import Sure

@Suite("Transaction date window")
struct TransactionDateWindowTests {
  @Test("Uses inclusive rolling 7- and 31-day windows")
  func inclusiveRollingWindows() throws {
    let calendar = calendar(timeZone: try #require(TimeZone(identifier: "UTC")))
    let endingAt = try date(2026, 8, 28, hour: 12, calendar: calendar)

    let sevenDays = try TransactionDateWindow(
      inclusiveDayCount: 7,
      endingAt: endingAt,
      calendar: calendar
    )
    let thirtyOneDays = try TransactionDateWindow(
      inclusiveDayCount: 31,
      endingAt: endingAt,
      calendar: calendar
    )

    #expect(sevenDays.startDate.iso8601String == "2026-08-22")
    #expect(sevenDays.endDate.iso8601String == "2026-08-28")
    #expect(sevenDays.contains(try LocalDate(year: 2026, month: 8, day: 22)))
    #expect(sevenDays.contains(try LocalDate(year: 2026, month: 8, day: 28)))
    #expect(!sevenDays.contains(try LocalDate(year: 2026, month: 8, day: 21)))
    #expect(!sevenDays.contains(try LocalDate(year: 2026, month: 8, day: 29)))
    #expect(thirtyOneDays.startDate.iso8601String == "2026-07-29")
    #expect(thirtyOneDays.endDate.iso8601String == "2026-08-28")
  }

  @Test("Crosses a leap-month boundary by calendar days")
  func leapMonthBoundary() throws {
    let calendar = calendar(timeZone: try #require(TimeZone(identifier: "UTC")))
    let endingAt = try date(2028, 3, 1, hour: 12, calendar: calendar)

    let window = try TransactionDateWindow(
      inclusiveDayCount: 31,
      endingAt: endingAt,
      calendar: calendar
    )

    #expect(window.startDate.iso8601String == "2028-01-31")
    #expect(window.endDate.iso8601String == "2028-03-01")
  }

  @Test("Crosses a year boundary by calendar days")
  func yearBoundary() throws {
    let calendar = calendar(timeZone: try #require(TimeZone(identifier: "UTC")))
    let endingAt = try date(2026, 1, 3, hour: 12, calendar: calendar)

    let window = try TransactionDateWindow(
      inclusiveDayCount: 31,
      endingAt: endingAt,
      calendar: calendar
    )

    #expect(window.startDate.iso8601String == "2025-12-04")
    #expect(window.endDate.iso8601String == "2026-01-03")
  }

  @Test("Uses local calendar days across Los Angeles daylight saving time")
  func daylightSavingBoundary() throws {
    let calendar = calendar(
      timeZone: try #require(TimeZone(identifier: "America/Los_Angeles"))
    )
    let endingAt = try date(2026, 3, 10, hour: 0, minute: 30, calendar: calendar)

    let window = try TransactionDateWindow(
      inclusiveDayCount: 7,
      endingAt: endingAt,
      calendar: calendar
    )

    #expect(window.startDate.iso8601String == "2026-03-04")
    #expect(window.endDate.iso8601String == "2026-03-10")
  }

  @Test("The same instant resolves to each configured time zone's local day")
  func sameInstantTimeZones() throws {
    let utc = calendar(timeZone: try #require(TimeZone(identifier: "UTC")))
    let instant = try date(2026, 1, 1, hour: 0, minute: 30, calendar: utc)
    let losAngeles = calendar(
      timeZone: try #require(TimeZone(identifier: "America/Los_Angeles"))
    )
    let tokyo = calendar(timeZone: try #require(TimeZone(identifier: "Asia/Tokyo")))

    let losAngelesWindow = try TransactionDateWindow(
      inclusiveDayCount: 7,
      endingAt: instant,
      calendar: losAngeles
    )
    let tokyoWindow = try TransactionDateWindow(
      inclusiveDayCount: 7,
      endingAt: instant,
      calendar: tokyo
    )

    #expect(losAngelesWindow.startDate.iso8601String == "2025-12-25")
    #expect(losAngelesWindow.endDate.iso8601String == "2025-12-31")
    #expect(tokyoWindow.startDate.iso8601String == "2025-12-26")
    #expect(tokyoWindow.endDate.iso8601String == "2026-01-01")
  }

  @Test("Rejects empty and reversed windows")
  func invalidWindows() throws {
    let calendar = calendar(timeZone: try #require(TimeZone(identifier: "UTC")))
    let endingAt = try date(2026, 8, 28, hour: 12, calendar: calendar)

    #expect(throws: (any Error).self) {
      try TransactionDateWindow(
        inclusiveDayCount: 0,
        endingAt: endingAt,
        calendar: calendar
      )
    }
    #expect(throws: (any Error).self) {
      try TransactionDateWindow(
        startDate: LocalDate(year: 2026, month: 8, day: 29),
        endDate: LocalDate(year: 2026, month: 8, day: 28)
      )
    }
  }

  private func calendar(timeZone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = timeZone
    return calendar
  }

  private func date(
    _ year: Int,
    _ month: Int,
    _ day: Int,
    hour: Int,
    minute: Int = 0,
    calendar: Calendar
  ) throws -> Date {
    try #require(
      calendar.date(
        from: DateComponents(
          calendar: calendar,
          timeZone: calendar.timeZone,
          year: year,
          month: month,
          day: day,
          hour: hour,
          minute: minute
        )
      )
    )
  }
}
