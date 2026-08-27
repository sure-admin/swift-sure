import Foundation
import Observation

@MainActor
@Observable
final class FinanceDataStore {
  static let shared = FinanceDataStore()

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
    return transactions.filter { Calendar.current.isDate($0.date, equalTo: reportingDate, toGranularity: .month) }
  }

  var reportingDate: Date? {
    transactions.first?.date
  }

  var reportingPeriodLabel: String {
    reportingDate?.formatted(.dateTime.month(.wide).year()) ?? "Latest period"
  }

  private init() { }

  func refresh() async {
    let connection = SureConnection.shared
    guard connection.isConfigured else {
      state = .needsConnection
      return
    }
    state = .loading
    do {
      let client = SureAPIClient(connection: connection)
      async let loadedAccounts = client.fetchAccounts()
      async let loadedTransactions = client.fetchTransactions()
      accounts = try await loadedAccounts
      transactions = try await loadedTransactions
      budgets = (try? await client.fetchBudgetCategories()) ?? []
      lastUpdated = .now
      state = .loaded
      await refreshInsights(using: client)
    } catch {
      state = .failed(error.localizedDescription)
    }
  }

  private func refreshInsights(using client: SureAPIClient) async {
    isLoadingInsights = true
    insightError = nil
    do {
      insights = try await client.fetchInsights()
    } catch {
      insights = []
      insightError = error.localizedDescription
    }
    #if os(iOS)
    WatchInsightsSync.shared.send(insights)
    #endif
    isLoadingInsights = false
  }
}

enum FinanceDataState: Equatable {
  case idle
  case loading
  case loaded
  case needsConnection
  case failed(String)
}
