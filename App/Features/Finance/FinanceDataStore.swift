import Foundation
import Observation

/// A screen-facing projection. Resources publish independently and retain their own freshness.
@MainActor
@Observable
final class FinanceDataStore {
  let balanceSheetResource = FinanceResource<BalanceSheetRecord?>(nil)
  let accountsResource = FinanceResource<[FinanceAccount]>([])
  let transactionsResource = FinanceResource<[FinanceTransaction]>([])
  let budgetsResource = FinanceResource<[BudgetCategory]>([])
  let insightsResource = FinanceResource<[BackendInsight]>([])
  let summaryResource = FinanceResource<FinancialSummary?>(nil)
  let reporting: ReportingPeriodStore
  private let sync = FinanceSyncCoordinator()
  private let connection: any ConnectionStateProviding
  private let client: any FinanceDataClient
  private let summaries: (any FinancialSummaryProviding)?
  private let now: () -> Date
  private let syncInsights: ([BackendInsight]) -> Void
  private var hasRequestedSessionRefresh = false
  private var disconnected = false
  private var generation = 0

  init(connection: any ConnectionStateProviding, client: any FinanceDataClient,
       calendar: Calendar, now: @escaping () -> Date,
       summaries: (any FinancialSummaryProviding)? = nil,
       syncInsights: @escaping ([BackendInsight]) -> Void) {
    self.connection = connection; self.client = client; self.now = now
    self.summaries = summaries; self.syncInsights = syncInsights
    reporting = ReportingPeriodStore(calendar: calendar, now: now)
  }

  var balanceSheet: BalanceSheetRecord? { get { balanceSheetResource.value } set { balanceSheetResource.value = newValue } }
  var accounts: [FinanceAccount] { get { accountsResource.value } set { accountsResource.value = newValue } }
  var transactions: [FinanceTransaction] { get { transactionsResource.value } set { transactionsResource.value = newValue } }
  var budgets: [BudgetCategory] { get { budgetsResource.value } set { budgetsResource.value = newValue } }
  var insights: [BackendInsight] { get { insightsResource.value } set { insightsResource.value = newValue } }
  var balanceSheetError: String? { balanceSheetResource.failure?.localizedDescription }
  var accountsError: String? { accountsResource.failure?.localizedDescription }
  var transactionsError: String? { transactionsResource.failure?.localizedDescription }
  var budgetError: String? { budgetsResource.failure?.localizedDescription }
  var insightError: String? { insightsResource.failure?.localizedDescription }
  var summaryError: String? { summaryResource.failure?.localizedDescription }
  var isLoadingInsights: Bool { insightsResource.isLoading }
  var isLoadingReportingPeriod: Bool { summaryResource.isLoading }
  var netWorth: DecimalMoney? { balanceSheet?.netWorth }
  var periodIncome: DecimalMoney? { currentSummary?.income }
  var periodSpending: DecimalMoney? { currentSummary?.spending }
  var savingsRate: Decimal? { currentSummary?.savingsRate }
  var currentSummary: FinancialSummary? { summaryResource.value.flatMap { $0.month == reporting.month ? $0 : nil } }
  var reportingDate: LocalDate? { reporting.month.start }
  var reportingPeriodLabel: String { reporting.label }
  var canSelectNextReportingMonth: Bool { reporting.canSelectNext }
  var reportingPeriodTransactions: [FinanceTransaction] {
    transactions.filter { SpendingMonth(containing: $0.date) == reporting.month }
  }
  var recentActivityTransactions: [FinanceTransaction] {
    guard let window = try? TransactionDateWindow(inclusiveDayCount: 7, endingAt: now(), calendar: reporting.calendar) else { return [] }
    return transactions.filter { window.contains($0.date) }.sorted {
      $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date > $1.date
    }
  }
  var lastUpdated: Date? {
    let dates = [balanceSheetResource.metadata, accountsResource.metadata, transactionsResource.metadata].compactMap { $0?.fetchedAt }
    return dates.count == 3 ? dates.min() : nil
  }
  var state: FinanceDataState {
    if !connection.isConfigured || disconnected { return .needsConnection }
    if balanceSheetResource.hasValue || accountsResource.hasValue || transactionsResource.hasValue || budgetsResource.hasValue || insightsResource.hasValue { return .loaded }
    if sync.isLoading { return .loading }
    if let failure = [balanceSheetResource.failure, accountsResource.failure, transactionsResource.failure,
                      budgetsResource.failure, insightsResource.failure].compactMap({ $0 }).first { return .failed(failure.localizedDescription) }
    return .idle
  }

  func refreshIfNeeded() async { if !hasRequestedSessionRefresh { await refresh() } }

  func refresh() async {
    guard connection.isConfigured else { return }
    let request = generation
    disconnected = false
    hasRequestedSessionRefresh = true
    await restoreSnapshotIfAvailable()
    guard generation == request, connection.isConfigured else { return }
    await sync.refresh([
      { [self] in _ = await balanceSheetResource.load(now: now, metadata: { await self.client.readMetadata(for: "balance-sheet") }) { try await self.client.fetchBalanceSheet() } },
      { [self] in _ = await accountsResource.load(now: now, metadata: { await self.client.readMetadata(for: "accounts") }) { try await self.client.fetchAccounts() } },
      { [self] in await loadRecentTransactions() },
      { [self] in _ = await budgetsResource.load(now: now, metadata: { await self.client.readMetadata(for: "budgets") }) { try await self.client.fetchBudgetCategories() } },
      { [self] in
        let live = await insightsResource.load(now: now, metadata: { await self.client.readMetadata(for: "insights") }) { try await self.client.fetchInsights() }
        if live { syncInsights(insights) }
      },
      { [self] in await loadSummary() }
    ])
  }

  func selectPreviousReportingMonth() async { await selectMonth(offset: -1) }
  func selectNextReportingMonth() async { if reporting.canSelectNext { await selectMonth(offset: 1) } }
  private func selectMonth(offset: Int) async {
    guard connection.isConfigured else { return }
    reporting.select(offset: offset)
    summaryResource.clear()
    await loadSummary()
  }
  private func loadSummary() async {
    guard let summaries else { return }
    let month = reporting.month
    _ = await summaryResource.load(now: now, metadata: { await self.client.readMetadata(for: "summary/" + month.start.iso8601String) }) {
      try await summaries.fetchSummary(for: month)
    }
  }
  private func loadRecentTransactions() async {
    let window = try? recentWindow()
    _ = await transactionsResource.load(now: now, metadata: {
      guard let window else { return nil }
      return await self.client.readMetadata(for: "transactions/all/\(window.startDate.iso8601String)/\(window.endDate.iso8601String)")
    }) {
      guard let window else { throw DataFailure.validation }
      return try await self.client.fetchTransactions(in: window)
    }
  }
  private func recentWindow() throws -> TransactionDateWindow {
    try TransactionDateWindow(inclusiveDayCount: 7, endingAt: now(), calendar: reporting.calendar)
  }

  func restoreSnapshotIfAvailable() async {
    let request = generation
    guard connection.isConfigured, let snapshot = await client.cachedSnapshot(), request == generation,
          connection.isConfigured else { return }
    let balance = await client.readMetadata(for: "balance-sheet")
    let accounts = await client.readMetadata(for: "accounts")
    let budgets = await client.readMetadata(for: "budgets")
    let insights = await client.readMetadata(for: "insights")
    let preview = await client.readMetadata(for: "legacy-preview")
    guard request == generation, connection.isConfigured else { return }
    if let preview, let window = try? recentWindow() {
      transactionsResource.restore(snapshot.transactions.filter { window.contains($0.date) }, metadata: preview)
    }
    if let balance { balanceSheetResource.restore(snapshot.balanceSheet, metadata: balance) }
    if let accounts { accountsResource.restore(snapshot.accounts, metadata: accounts) }
    if let budgets { budgetsResource.restore(snapshot.budgets, metadata: budgets) }
    if let insights { insightsResource.restore(snapshot.insights, metadata: insights) }
  }

  func suspendSync() {
    generation &+= 1; sync.cancel(); hasRequestedSessionRefresh = false
    balanceSheetResource.suspend(); accountsResource.suspend(); transactionsResource.suspend()
    budgetsResource.suspend(); insightsResource.suspend(); summaryResource.suspend()
  }
  func disconnect(preservingSnapshot: Bool = false) {
    suspendSync(); disconnected = true
    balanceSheetResource.clear(); accountsResource.clear(); transactionsResource.clear()
    budgetsResource.clear(); insightsResource.clear(); summaryResource.clear()
    syncInsights([])
  }
}
