import Foundation
import Testing
@testable import Sure

@MainActor
struct ReportingPeriodStoreTests {
  @Test("Early-month reporting selects the previous Gregorian month", arguments: [1, 2, 3, 4])
  func earlyMonth(day: Int) {
    let date = testReadCalendar.date(from: DateComponents(year: 2024, month: 1, day: day))!
    let store = ReportingPeriodStore(calendar: testReadCalendar, now: { date })
    #expect(store.month.start.iso8601String == (day <= 3 ? "2023-12-01" : "2024-01-01"))
    store.select(offset: 2)
    #expect(store.month.start.iso8601String == "2024-01-01")
    #expect(!store.canSelectNext)
  }
}
