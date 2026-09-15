import Foundation
import Observation

@MainActor
@Observable
final class ReportingPeriodStore {
  private(set) var month: SpendingMonth
  let calendar: Calendar
  private let now: () -> Date

  init(calendar: Calendar, now: @escaping () -> Date) {
    var gregorian = Calendar(identifier: .gregorian)
    gregorian.timeZone = calendar.timeZone
    self.calendar = gregorian; self.now = now
    let today = try! LocalDate(now(), in: gregorian)
    let current = SpendingMonth(containing: today)
    month = today.day <= 3 ? current.shifted(by: -1) : current
  }

  var canSelectNext: Bool { month < currentMonth }
  var label: String { FinanceFormatters.monthAndYear(month.start, calendar: calendar) }
  func select(offset: Int) { month = min(month.shifted(by: offset), currentMonth) }
  private var currentMonth: SpendingMonth { SpendingMonth(containing: try! LocalDate(now(), in: calendar)) }
}

extension SpendingMonth: Comparable {
  static func < (lhs: SpendingMonth, rhs: SpendingMonth) -> Bool { lhs.start < rhs.start }
}
