import Foundation

struct LocalDate: Codable, Comparable, Hashable, Sendable {
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

  init(_ date: Date, in calendar: Calendar) throws {
    var gregorianCalendar = Self.calendar
    gregorianCalendar.timeZone = calendar.timeZone
    let components = gregorianCalendar.dateComponents([.year, .month, .day], from: date)
    guard let year = components.year,
          let month = components.month,
          let day = components.day else {
      throw LocalDateError.invalidDate
    }
    try self.init(year: year, month: month, day: day)
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

  static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
    if lhs.year != rhs.year { return lhs.year < rhs.year }
    if lhs.month != rhs.month { return lhs.month < rhs.month }
    return lhs.day < rhs.day
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
