import Foundation

struct LocalDate: Codable, Equatable, Hashable, Sendable {
  let year: Int
  let month: Int
  let day: Int

  init(year: Int, month: Int, day: Int) throws {
    var components = DateComponents()
    components.calendar = Self.calendar
    components.timeZone = Self.calendar.timeZone
    components.year = year
    components.month = month
    components.day = day
    guard let date = Self.calendar.date(from: components) else {
      throw LocalDateError.invalidDate
    }
    let resolved = Self.calendar.dateComponents([.year, .month, .day], from: date)
    guard resolved.year == year, resolved.month == month, resolved.day == day else {
      throw LocalDateError.invalidDate
    }
    self.year = year
    self.month = month
    self.day = day
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let value = try container.decode(String.self)
    let parts = value.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 3,
          parts[0].count == 4,
          parts[1].count == 2,
          parts[2].count == 2,
          let year = Int(parts[0]),
          let month = Int(parts[1]),
          let day = Int(parts[2]) else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Expected a date in yyyy-MM-dd format."
      )
    }
    do {
      try self.init(year: year, month: month, day: day)
    } catch {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Expected a valid Gregorian calendar date."
      )
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(iso8601String)
  }

  var iso8601String: String {
    String(format: "%04d-%02d-%02d", year, month, day)
  }

  // The legacy UI still requires an absolute Date. Constructing noon in its
  // display calendar keeps the server's date-only value on the intended day.
  func legacyDate(in displayCalendar: Calendar = .autoupdatingCurrent) -> Date {
    var calendar = Self.calendar
    calendar.timeZone = displayCalendar.timeZone
    var components = DateComponents()
    components.calendar = calendar
    components.timeZone = calendar.timeZone
    components.year = year
    components.month = month
    components.day = day
    components.hour = 12
    return calendar.date(from: components)!
  }

  private static var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }
}

private enum LocalDateError: Error {
  case invalidDate
}
