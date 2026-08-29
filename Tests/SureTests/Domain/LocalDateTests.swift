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

  @Test("Derives the local calendar day at extreme time-zone offsets")
  func timeZoneDerivation() throws {
    let instant = try #require(
      ISO8601DateFormatter().date(from: "2026-12-31T23:30:00Z")
    )
    var west = Calendar(identifier: .gregorian)
    west.timeZone = try #require(TimeZone(secondsFromGMT: -43_200))
    var east = Calendar(identifier: .gregorian)
    east.timeZone = try #require(TimeZone(secondsFromGMT: 50_400))

    #expect(try LocalDate(instant, in: west) == LocalDate(year: 2026, month: 12, day: 31))
    #expect(try LocalDate(instant, in: east) == LocalDate(year: 2027, month: 1, day: 1))
  }
}
