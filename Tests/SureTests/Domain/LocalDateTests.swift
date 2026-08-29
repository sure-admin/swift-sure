import Foundation
import Testing
@testable import Sure

@Suite("Local date")
struct LocalDateTests {
  @Test("Round trips the server date-only representation")
  func roundTrip() throws {
    let date = try LocalDate(year: 2028, month: 2, day: 29)
    let data = try JSONEncoder().encode(date)
    #expect(String(decoding: data, as: UTF8.self) == #""2028-02-29""#)
    #expect(try JSONDecoder().decode(LocalDate.self, from: data) == date)
  }

  @Test("Rejects an invalid calendar date")
  func invalidDate() {
    do {
      _ = try LocalDate(year: 2027, month: 2, day: 29)
      #expect(Bool(false))
    } catch {
      #expect(Bool(true))
    }
  }

  @Test("Preserves the display day at extreme time-zone offsets")
  func displayTimeZones() throws {
    let localDate = try LocalDate(year: 2026, month: 12, day: 31)

    for secondsFromGMT in [-43_200, 50_400] {
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = try #require(TimeZone(secondsFromGMT: secondsFromGMT))
      let components = calendar.dateComponents(
        [.year, .month, .day, .hour],
        from: localDate.legacyDate(in: calendar)
      )

      #expect(components.year == 2026)
      #expect(components.month == 12)
      #expect(components.day == 31)
      #expect(components.hour == 12)
    }
  }
}
