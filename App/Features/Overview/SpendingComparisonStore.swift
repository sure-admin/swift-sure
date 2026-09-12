import Foundation
import Observation

@MainActor
@Observable
final class SpendingComparisonStore {
  private(set) var state: State = .idle
  private(set) var months: [SpendingMonth] = []
  private(set) var selectedMonth: SpendingMonth?

  private let client: any SpendingComparisonClient
  private let now: () -> Date
  private let calendar: Calendar
  private let connection: any ConnectionStateProviding
  private var generation = 0

  init(
    client: any SpendingComparisonClient,
    connection: any ConnectionStateProviding,
    calendar: Calendar,
    now: @escaping () -> Date
  ) {
    self.client = client
    self.connection = connection
    self.calendar = calendar
    self.now = now
    updateMonths()
  }

  func select(_ month: SpendingMonth) async {
    guard months.contains(month), month != selectedMonth else { return }
    selectedMonth = month
    await refresh()
  }

  func refreshIfNeeded() async {
    if state == .idle { await refresh() }
  }

  func refresh() async {
    updateMonths()
    generation += 1
    let requestGeneration = generation
    guard connection.isConfigured, let month = selectedMonth else {
      state = .idle
      return
    }
    state = .loading
    do {
      let comparison = try await client.fetchComparison(for: month)
      try Task.checkCancellation()
      guard generation == requestGeneration, connection.isConfigured else { return }
      guard comparison.month == month else {
        state = .failed
        return
      }
      state = .loaded(comparison)
    } catch {
      guard generation == requestGeneration, connection.isConfigured else { return }
      if error is CancellationError || (error as? URLError)?.code == .cancelled || Task.isCancelled {
        state = .idle
      } else if let error = error as? SpendingComparisonServiceError, error == .unavailable {
        state = .unavailable
      } else {
        // Never expose raw service errors, which could include financial data.
        state = .failed
      }
    }
  }

  func invalidate() {
    generation += 1
    state = .idle
    selectedMonth = nil
    updateMonths()
  }

  private func updateMonths() {
    guard let today = try? LocalDate(now(), in: calendar) else { return }
    let current = SpendingMonth(containing: today)
    let wasCurrent = selectedMonth == months.first
    months = (0..<12).map { current.shifted(by: -$0) }
    if wasCurrent || selectedMonth == nil || !months.contains(selectedMonth!) {
      selectedMonth = current
    }
  }

  enum State: Equatable {
    case idle, loading, unavailable, failed
    case loaded(SpendingComparison)
  }
}
