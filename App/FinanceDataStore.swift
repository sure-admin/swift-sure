import Foundation
import Observation

@MainActor
@Observable
final class FinanceDataStore {
  static let shared = makeLive()

  var accounts: [FinanceAccount] = []
  var transactions: [FinanceTransaction] = []
  var budgets: [BudgetCategory] = []
  var insights: [BackendInsight] = []
  var isLoadingInsights = false
  var insightError: String?
  var state: FinanceDataState = .idle
  var lastUpdated: Date?

  var netWorth: Double {
    accounts.reduce(0) { $0 + $1.balance }
  }

  var periodIncome: Double {
    reportingPeriodTransactions
      .filter { $0.kind == .income }
      .reduce(0) { $0 + abs($1.amount) }
  }

  var periodSpending: Double {
    reportingPeriodTransactions
      .filter { $0.kind == .expense }
      .reduce(0) { $0 + abs($1.amount) }
  }

  var reportingPeriodTransactions: [FinanceTransaction] {
    guard let reportingDate else { return [] }
    return transactions.filter { calendar.isDate($0.date, equalTo: reportingDate, toGranularity: .month) }
  }

  var recentActivityTransactions: [FinanceTransaction] {
    guard let window = try? TransactionDateWindow(
      inclusiveDayCount: 7,
      endingAt: now(),
      calendar: calendar
    ) else {
      return []
    }

    return transactions
      .filter { transaction in
        guard let localDate = try? LocalDate(transaction.date, in: calendar) else {
          return false
        }
        return window.contains(localDate)
      }
      .sorted { lhs, rhs in
        if lhs.date == rhs.date { return lhs.id < rhs.id }
        return lhs.date > rhs.date
      }
  }

  var reportingDate: Date? {
    transactions.first?.date
  }

  var reportingPeriodLabel: String {
    let style = Date.FormatStyle(
      calendar: calendar,
      timeZone: calendar.timeZone
    )
      .month(.wide)
      .year()
    return reportingDate?.formatted(style) ?? "Latest period"
  }

  private let connection: any ConnectionStateProviding
  private let client: any FinanceDataClient
  private let calendar: Calendar
  private let now: () -> Date
  private let syncInsights: ([BackendInsight]) -> Void

  init(
    connection: any ConnectionStateProviding,
    client: any FinanceDataClient,
    calendar: Calendar,
    now: @escaping () -> Date,
    syncInsights: @escaping ([BackendInsight]) -> Void
  ) {
    self.connection = connection
    self.client = client
    self.calendar = calendar
    self.now = now
    self.syncInsights = syncInsights
  }

  func refresh() async {
    guard connection.isConfigured else {
      state = .needsConnection
      return
    }
    let previousState = state
    state = .loading
    do {
      async let loadedAccounts = client.fetchAccounts()
      async let loadedTransactions = client.fetchTransactions()
      let refreshedAccounts = try await loadedAccounts
      let refreshedTransactions = try await loadedTransactions
      let refreshedBudgets: [BudgetCategory]
      do {
        refreshedBudgets = try await client.fetchBudgetCategories()
      } catch {
        guard !Self.isCancellation(error) else { throw CancellationError() }
        refreshedBudgets = []
      }
      try Task.checkCancellation()
      accounts = refreshedAccounts
      transactions = refreshedTransactions
      budgets = refreshedBudgets
      lastUpdated = now()
      state = .loaded
      await refreshInsights()
    } catch {
      if Self.isCancellation(error) {
        state = previousState
      } else {
        state = .failed(error.localizedDescription)
      }
    }
  }

  func disconnect() {
    accounts = []
    transactions = []
    budgets = []
    insights = []
    isLoadingInsights = false
    insightError = nil
    lastUpdated = nil
    state = .needsConnection
    syncInsights([])
  }

  private func refreshInsights() async {
    isLoadingInsights = true
    insightError = nil
    do {
      insights = try await client.fetchInsights()
    } catch {
      guard !Self.isCancellation(error) else {
        isLoadingInsights = false
        return
      }
      insights = []
      insightError = error.localizedDescription
    }
    syncInsights(insights)
    isLoadingInsights = false
  }

  private static func isCancellation(_ error: Error) -> Bool {
    if error is CancellationError || Task.isCancelled { return true }
    return (error as? URLError)?.code == .cancelled
  }

  private static func makeLive() -> FinanceDataStore {
    let connection = SureConnection.shared
    let client = SureAPIClient(connection: connection)
    #if os(iOS)
    let syncInsights: ([BackendInsight]) -> Void = { insights in
      WatchInsightsSync.shared.send(insights)
    }
    #else
    let syncInsights: ([BackendInsight]) -> Void = { _ in }
    #endif
    return FinanceDataStore(
      connection: connection,
      client: client,
      calendar: .autoupdatingCurrent,
      now: { .now },
      syncInsights: syncInsights
    )
  }
}

enum FinanceDataState: Equatable {
  case idle
  case loading
  case loaded
  case needsConnection
  case failed(String)
}
