import Foundation
import Observation

@MainActor
@Observable
final class FinanceDataStore {
  var balanceSheet: BalanceSheetRecord?
  var accounts: [FinanceAccount] = []
  var transactions: [FinanceTransaction] = []
  var budgets: [BudgetCategory] = []
  var budgetError: String?
  var insights: [BackendInsight] = []
  var isLoadingInsights = false
  var insightError: String?
  var state: FinanceDataState = .idle
  var lastUpdated: Date?

  var netWorth: Money? {
    balanceSheet?.netWorth
  }

  var periodIncome: MoneyBreakdown {
    MoneyBreakdown(aggregating: reportingPeriodTransactions
      .filter { $0.kind == .income }
      .map(\.amount))
  }

  var periodSpending: MoneyBreakdown {
    MoneyBreakdown(aggregating: reportingPeriodTransactions
      .filter { $0.kind == .expense }
      .map(\.amount))
  }

  var savingsRate: Decimal? {
    guard periodIncome.isAvailable,
          periodSpending.isAvailable,
          let income = periodIncome.singleAmount,
          income.decimalValue > 0 else {
      return nil
    }
    let spending: Money
    if let amount = periodSpending.singleAmount {
      guard amount.currency == income.currency else { return nil }
      spending = amount
    } else if periodSpending.amounts.isEmpty {
      spending = Money(minorUnits: 0, currency: income.currency)
    } else {
      return nil
    }
    return max(
      Decimal.zero,
      (income.decimalValue - spending.decimalValue) / income.decimalValue
    )
  }

  var reportingPeriodTransactions: [FinanceTransaction] {
    guard let reportingDate else { return [] }
    return transactions.filter {
      $0.date.year == reportingDate.year && $0.date.month == reportingDate.month
    }
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
      .filter { window.contains($0.date) }
      .sorted { lhs, rhs in
        if lhs.date == rhs.date { return lhs.id.uuidString < rhs.id.uuidString }
        return lhs.date > rhs.date
      }
  }

  var reportingDate: LocalDate? {
    transactions.first?.date
  }

  var reportingPeriodLabel: String {
    guard let reportingDate else { return "Latest period" }
    return FinanceFormatters.monthAndYear(reportingDate, calendar: calendar)
  }

  private let connection: any ConnectionStateProviding
  private let client: any FinanceDataClient
  private let calendar: Calendar
  private let now: () -> Date
  private let syncInsights: ([BackendInsight]) -> Void
  private var generation = 0

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
    let refreshGeneration = generation
    state = .loading
    do {
      async let loadedBalanceSheet = client.fetchBalanceSheet()
      async let loadedAccounts = client.fetchAccounts()
      async let loadedTransactions = client.fetchTransactions()
      let refreshedBalanceSheet = try await loadedBalanceSheet
      let refreshedAccounts = try await loadedAccounts
      let refreshedTransactions = try await loadedTransactions
      let refreshedBudgets: [BudgetCategory]
      let refreshedBudgetError: String?
      do {
        refreshedBudgets = try await client.fetchBudgetCategories()
        refreshedBudgetError = nil
      } catch {
        guard !Self.isCancellation(error) else { throw CancellationError() }
        refreshedBudgets = []
        refreshedBudgetError = error.localizedDescription
      }
      try Task.checkCancellation()
      guard generation == refreshGeneration, connection.isConfigured else { return }
      balanceSheet = refreshedBalanceSheet
      accounts = refreshedAccounts
      transactions = refreshedTransactions
      budgets = refreshedBudgets
      budgetError = refreshedBudgetError
      lastUpdated = now()
      state = .loaded
      await refreshInsights(generation: refreshGeneration)
    } catch {
      guard generation == refreshGeneration else { return }
      if Self.isCancellation(error) {
        state = previousState
      } else {
        state = .failed(error.localizedDescription)
      }
    }
  }

  func disconnect() {
    generation += 1
    balanceSheet = nil
    accounts = []
    transactions = []
    budgets = []
    budgetError = nil
    insights = []
    isLoadingInsights = false
    insightError = nil
    lastUpdated = nil
    state = .needsConnection
    syncInsights([])
  }

  private func refreshInsights(generation refreshGeneration: Int) async {
    isLoadingInsights = true
    insightError = nil
    do {
      let refreshedInsights = try await client.fetchInsights()
      guard generation == refreshGeneration, connection.isConfigured else { return }
      insights = refreshedInsights
    } catch {
      guard generation == refreshGeneration else { return }
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

}
