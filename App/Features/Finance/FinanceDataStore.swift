import Foundation
import Observation

@MainActor
@Observable
final class FinanceDataStore {
  var balanceSheet: BalanceSheetRecord?
  var balanceSheetError: String?
  var accounts: [FinanceAccount] = []
  var accountsError: String?
  var transactions: [FinanceTransaction] = []
  var transactionsError: String?
  var budgets: [BudgetCategory] = []
  var budgetError: String?
  var insights: [BackendInsight] = []
  var isLoadingInsights = false
  var insightError: String?
  var state: FinanceDataState = .idle
  var lastUpdated: Date?

  var netWorth: DecimalMoney? {
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
    try? LocalDate(now(), in: calendar)
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
  private var refreshSequence = 0
  private var activeRefresh: ActiveRefresh?

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
    if let activeRefresh {
      await activeRefresh.task.value
      return
    }

    refreshSequence &+= 1
    let refreshID = refreshSequence
    let task = Task { @MainActor [weak self] in
      guard let self else { return }
      await self.performRefresh()
    }
    activeRefresh = ActiveRefresh(id: refreshID, task: task)
    await task.value
    if activeRefresh?.id == refreshID {
      activeRefresh = nil
    }
  }

  private func performRefresh() async {
    guard connection.isConfigured else {
      state = .needsConnection
      return
    }
    let previousState = state
    let refreshGeneration = generation
    var didPublishFinance = false
    state = .loading
    isLoadingInsights = true
    do {
      let transactionWindow = try TransactionDateWindow(
        inclusiveDayCount: 31,
        endingAt: now(),
        calendar: calendar
      )
      async let loadedBalanceSheet = capture { try await client.fetchBalanceSheet() }
      async let loadedAccounts = capture { try await client.fetchAccounts() }
      async let loadedTransactions = capture {
        try await client.fetchTransactions(in: transactionWindow)
      }
      async let loadedBudgets = capture { try await client.fetchBudgetCategories() }
      async let loadedInsights = capture { try await client.fetchInsights() }
      let financeResults = await (
        balanceSheet: loadedBalanceSheet,
        accounts: loadedAccounts,
        transactions: loadedTransactions,
        budgets: loadedBudgets
      )
      try Task.checkCancellation()
      guard !Self.wasCancelled(financeResults.balanceSheet),
            !Self.wasCancelled(financeResults.accounts),
            !Self.wasCancelled(financeResults.transactions),
            !Self.wasCancelled(financeResults.budgets) else {
        throw CancellationError()
      }
      guard generation == refreshGeneration, connection.isConfigured else { return }

      var successfulLoads = 0
      var failureMessages: [String] = []
      var didRefreshBalanceSheet = false
      var didRefreshAccounts = false
      var didRefreshTransactions = false
      switch financeResults.balanceSheet {
      case .success(let value):
        balanceSheet = value
        balanceSheetError = nil
        didRefreshBalanceSheet = true
        successfulLoads += 1
      case .failure(let error):
        balanceSheetError = error.localizedDescription
        failureMessages.append(error.localizedDescription)
      }
      switch financeResults.accounts {
      case .success(let value):
        accounts = value
        accountsError = nil
        didRefreshAccounts = true
        successfulLoads += 1
      case .failure(let error):
        accountsError = error.localizedDescription
        failureMessages.append(error.localizedDescription)
      }
      switch financeResults.transactions {
      case .success(let value):
        transactions = value
        transactionsError = nil
        didRefreshTransactions = true
        successfulLoads += 1
      case .failure(let error):
        transactionsError = error.localizedDescription
        failureMessages.append(error.localizedDescription)
      }
      switch financeResults.budgets {
      case .success(let value):
        budgets = value
        budgetError = nil
        successfulLoads += 1
      case .failure(let error):
        budgetError = error.localizedDescription
        failureMessages.append(error.localizedDescription)
      }

      if successfulLoads > 0 {
        if didRefreshBalanceSheet && didRefreshAccounts && didRefreshTransactions {
          lastUpdated = now()
        }
        state = .loaded
        didPublishFinance = true
      }

      let insightResult = await loadedInsights
      try Task.checkCancellation()
      guard !Self.wasCancelled(insightResult) else {
        throw CancellationError()
      }
      guard generation == refreshGeneration, connection.isConfigured else { return }

      switch insightResult {
      case .success(let value):
        insights = value
        insightError = nil
        syncInsights(value)
        successfulLoads += 1
      case .failure(let error):
        insightError = error.localizedDescription
        failureMessages.append(error.localizedDescription)
      }
      isLoadingInsights = false

      if successfulLoads > 0 {
        state = .loaded
      } else {
        state = .failed(failureMessages.first ?? "Sure data is unavailable.")
      }
    } catch {
      guard generation == refreshGeneration else { return }
      isLoadingInsights = false
      if Self.isCancellation(error) {
        if !didPublishFinance {
          state = previousState
        }
      } else {
        state = .failed(error.localizedDescription)
      }
    }
  }

  func disconnect() {
    activeRefresh?.task.cancel()
    activeRefresh = nil
    generation += 1
    balanceSheet = nil
    balanceSheetError = nil
    accounts = []
    accountsError = nil
    transactions = []
    transactionsError = nil
    budgets = []
    budgetError = nil
    insights = []
    isLoadingInsights = false
    insightError = nil
    lastUpdated = nil
    state = .needsConnection
    syncInsights([])
  }

  private func capture<Value>(
    _ operation: () async throws -> Value
  ) async -> Result<Value, any Error> {
    do {
      return .success(try await operation())
    } catch {
      return .failure(error)
    }
  }

  private static func isCancellation(_ error: Error) -> Bool {
    if error is CancellationError || Task.isCancelled { return true }
    return (error as? URLError)?.code == .cancelled
  }

  private static func wasCancelled<Value>(
    _ result: Result<Value, any Error>
  ) -> Bool {
    guard case .failure(let error) = result else { return false }
    return isCancellation(error)
  }

  private struct ActiveRefresh {
    var id: Int
    var task: Task<Void, Never>
  }
}
