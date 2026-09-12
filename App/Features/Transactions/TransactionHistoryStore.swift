import Foundation
import Observation

@MainActor
@Observable
final class TransactionHistoryStore {
  private(set) var showingDownloadedData = false
  private var isOffline: () -> Bool
  private(set) var state: TransactionHistoryState = .idle
  private(set) var transactions: [FinanceTransaction] = []

  let scope: TransactionHistoryScope

  private let client: any TransactionHistoryClient
  private let calendar: Calendar
  private let now: () -> Date

  init(
    scope: TransactionHistoryScope,
    client: any TransactionHistoryClient,
    isOffline: @escaping () -> Bool = { false },
    calendar: Calendar,
    now: @escaping () -> Date
  ) {
    self.scope = scope
    self.client = client
    self.isOffline = isOffline
    self.calendar = calendar
    self.now = now
  }

  private var isInvalidated = false

  func invalidate() {
    isInvalidated = true
    transactions = []
    state = .idle
  }

  func load() async {
    guard !isInvalidated else { return }
    guard state != .loading else { return }

    let previousState = state
    let previousTransactions = transactions
    state = .loading
    transactions = []
    let referenceDate = now()

    do {
      let dateWindow = try TransactionDateWindow(
        inclusiveDayCount: scope.dayCount,
        endingAt: referenceDate,
        calendar: calendar
      )
      let request = TransactionHistoryRequest(
        accountID: scope.accountID,
        dateWindow: dateWindow
      )
      let wasOffline = isOffline()
      let loadedTransactions = try await client.fetchTransactions(request)
      showingDownloadedData = wasOffline
      try Task.checkCancellation()
      guard !isInvalidated else { return }
      transactions = loadedTransactions.sorted { lhs, rhs in
        if lhs.date == rhs.date { return lhs.id.uuidString < rhs.id.uuidString }
        return lhs.date > rhs.date
      }
      state = .loaded
    } catch {
      guard !isInvalidated else { return }
      if Self.isCancellation(error) {
        state = previousState
        transactions = previousTransactions
      } else if !previousTransactions.isEmpty {
        transactions = previousTransactions
        state = .loaded
      } else {
        state = .failed(error.localizedDescription)
      }
    }
  }

  private static func isCancellation(_ error: Error) -> Bool {
    if error is CancellationError || Task.isCancelled { return true }
    return (error as? URLError)?.code == .cancelled
  }
}

enum TransactionHistoryState: Equatable {
  case idle
  case loading
  case loaded
  case failed(String)
}
