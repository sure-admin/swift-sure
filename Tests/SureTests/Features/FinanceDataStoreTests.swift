import Foundation
import Testing
@testable import Sure

@MainActor
@Suite("Finance data store")
struct FinanceDataStoreTests {
  @Test("An unconfigured connection requires setup without loading data")
  func unconfiguredConnection() async {
    let client = FinanceDataClientStub()
    let insightSink = InsightSinkSpy()
    let store = makeStore(
      connection: ConnectionStateStub(isConfigured: false),
      client: client,
      insightSink: insightSink
    )

    await store.refresh()

    let calls = await client.recordedCalls()
    #expect(store.state == .needsConnection)
    #expect(calls.isEmpty)
    #expect(insightSink.sentInsightIDs.isEmpty)
  }

  @Test("A successful refresh publishes data and the injected timestamp")
  func successfulRefresh() async {
    let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)
    let account = FinanceAccount(
      id: "account-1",
      name: "Checking",
      institution: "Sure",
      kind: .cash,
      balance: 125,
      change: 0,
      tintName: "blue"
    )
    let transaction = FinanceTransaction(
      id: "transaction-1",
      merchant: "Market",
      category: "Groceries",
      symbol: "cart.fill",
      date: fixedNow,
      amount: 25,
      kind: .expense
    )
    let budget = BudgetCategory(
      id: "budget-1",
      name: "Groceries",
      symbol: "cart.fill",
      spent: 25,
      limit: 100
    )
    let insight = BackendInsight(
      id: "insight-1",
      type: "budget_on_track",
      title: "On track",
      body: "Spending is within the plan.",
      priority: "medium",
      status: "active",
      periodStart: nil,
      generatedAt: fixedNow
    )
    let client = FinanceDataClientStub(
      accountsResult: .success([account]),
      transactionsResult: .success([transaction]),
      budgetsResult: .success([budget]),
      insightsResult: .success([insight])
    )
    let insightSink = InsightSinkSpy()
    let store = makeStore(
      connection: ConnectionStateStub(isConfigured: true),
      client: client,
      insightSink: insightSink,
      now: { fixedNow }
    )

    await store.refresh()

    let calls = await client.recordedCalls()
    #expect(store.state == .loaded)
    #expect(store.accounts.map(\.id) == ["account-1"])
    #expect(store.transactions.map(\.id) == ["transaction-1"])
    #expect(store.budgets.map(\.id) == ["budget-1"])
    #expect(store.insights.map(\.id) == ["insight-1"])
    #expect(store.lastUpdated == fixedNow)
    #expect(store.insightError == nil)
    #expect(insightSink.sentInsightIDs == [["insight-1"]])
    #expect(calls.count == FinanceDataClientStub.Call.allCases.count)
    for call in FinanceDataClientStub.Call.allCases {
      #expect(calls.filter { $0 == call }.count == 1)
    }
  }

  @Test("A required data failure leaves the store failed")
  func requiredDataFailure() async {
    let client = FinanceDataClientStub(accountsResult: .failure(.expected))
    let store = makeStore(
      connection: ConnectionStateStub(isConfigured: true),
      client: client,
      insightSink: InsightSinkSpy()
    )

    await store.refresh()

    #expect(store.state == .failed("Expected failure"))
    #expect(store.lastUpdated == nil)
  }

  @Test("A budget failure degrades to an empty budget")
  func budgetFailure() async {
    let client = FinanceDataClientStub(budgetsResult: .failure(.expected))
    let store = makeStore(
      connection: ConnectionStateStub(isConfigured: true),
      client: client,
      insightSink: InsightSinkSpy()
    )

    await store.refresh()

    #expect(store.state == .loaded)
    #expect(store.budgets.isEmpty)
    #expect(store.insightError == nil)
  }

  @Test("An insight failure preserves finance data and reports the error")
  func insightFailure() async {
    let client = FinanceDataClientStub(insightsResult: .failure(.expected))
    let insightSink = InsightSinkSpy()
    let store = makeStore(
      connection: ConnectionStateStub(isConfigured: true),
      client: client,
      insightSink: insightSink
    )

    await store.refresh()

    #expect(store.state == .loaded)
    #expect(store.insights.isEmpty)
    #expect(store.insightError == "Expected failure")
    #expect(insightSink.sentInsightIDs == [[]])
  }

  @Test("Disconnect clears cached state and the synced insights")
  func disconnect() {
    let insightSink = InsightSinkSpy()
    let store = makeStore(
      connection: ConnectionStateStub(isConfigured: true),
      client: FinanceDataClientStub(),
      insightSink: insightSink
    )
    store.accounts = [
      FinanceAccount(
        id: "account-1",
        name: "Checking",
        institution: "Sure",
        kind: .cash,
        balance: 125,
        change: 0,
        tintName: "blue"
      )
    ]
    store.insights = [
      BackendInsight(
        id: "insight-1",
        type: "budget_on_track",
        title: "On track",
        body: "Spending is within the plan.",
        priority: "medium",
        status: "active",
        periodStart: nil,
        generatedAt: nil
      )
    ]
    store.lastUpdated = Date(timeIntervalSince1970: 1_800_000_000)

    store.disconnect()

    #expect(store.accounts.isEmpty)
    #expect(store.transactions.isEmpty)
    #expect(store.budgets.isEmpty)
    #expect(store.insights.isEmpty)
    #expect(store.lastUpdated == nil)
    #expect(store.state == .needsConnection)
    #expect(insightSink.sentInsightIDs == [[]])
  }

  @Test("Reporting periods use the injected calendar across a year boundary")
  func reportingPeriodCalendar() throws {
    let calendar = utcCalendar()
    let january31 = try #require(
      calendar.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 12))
    )
    let january1 = try #require(
      calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12))
    )
    let december31 = try #require(
      calendar.date(from: DateComponents(year: 2025, month: 12, day: 31, hour: 12))
    )
    let store = FinanceDataStore(
      connection: ConnectionStateStub(isConfigured: true),
      client: FinanceDataClientStub(),
      calendar: calendar,
      now: { january31 },
      syncInsights: { _ in }
    )
    store.transactions = [
      transaction(id: "january-31", date: january31),
      transaction(id: "january-1", date: january1),
      transaction(id: "december-31", date: december31)
    ]

    #expect(store.reportingPeriodTransactions.map(\.id) == ["january-31", "january-1"])
  }

  @Test("Recent activity uses the inclusive rolling seven-day window")
  func recentActivityWindow() throws {
    let calendar = utcCalendar()
    let today = try #require(
      calendar.date(from: DateComponents(year: 2026, month: 8, day: 28, hour: 12))
    )
    let firstIncludedDay = try #require(
      calendar.date(from: DateComponents(year: 2026, month: 8, day: 22, hour: 12))
    )
    let dayBeforeWindow = try #require(
      calendar.date(from: DateComponents(year: 2026, month: 8, day: 21, hour: 12))
    )
    let tomorrow = try #require(
      calendar.date(from: DateComponents(year: 2026, month: 8, day: 29, hour: 12))
    )
    let store = FinanceDataStore(
      connection: ConnectionStateStub(isConfigured: true),
      client: FinanceDataClientStub(),
      calendar: calendar,
      now: { today },
      syncInsights: { _ in }
    )
    store.transactions = [
      transaction(id: "before", date: dayBeforeWindow),
      transaction(id: "start", date: firstIncludedDay),
      transaction(id: "future", date: tomorrow),
      transaction(id: "today", date: today)
    ]

    #expect(store.recentActivityTransactions.map(\.id) == ["today", "start"])
  }

  @Test("Cancellation cannot publish a partially refreshed finance snapshot")
  func cancelledRefreshIsAtomic() async {
    let previousTimestamp = Date(timeIntervalSince1970: 1_700_000_000)
    let store = makeStore(
      connection: ConnectionStateStub(isConfigured: true),
      client: PartiallySuccessfulFinanceDataClient(),
      insightSink: InsightSinkSpy()
    )
    store.accounts = [FinanceAccount(
      id: "previous-account",
      name: "Previous account",
      institution: "Sure",
      kind: .cash,
      balance: 100,
      change: 0,
      tintName: "blue"
    )]
    store.transactions = [transaction(id: "previous-transaction", date: previousTimestamp)]
    store.budgets = [BudgetCategory(
      id: "previous-budget",
      name: "Previous budget",
      symbol: "cart.fill",
      spent: 10,
      limit: 100
    )]
    store.lastUpdated = previousTimestamp
    store.state = .loaded

    await store.refresh()

    #expect(store.state == .loaded)
    #expect(store.accounts.map(\.id) == ["previous-account"])
    #expect(store.transactions.map(\.id) == ["previous-transaction"])
    #expect(store.budgets.map(\.id) == ["previous-budget"])
    #expect(store.lastUpdated == previousTimestamp)
  }

  private func makeStore(
    connection: any ConnectionStateProviding,
    client: any FinanceDataClient,
    insightSink: InsightSinkSpy,
    now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_800_000_000) }
  ) -> FinanceDataStore {
    FinanceDataStore(
      connection: connection,
      client: client,
      calendar: utcCalendar(),
      now: now,
      syncInsights: { insightSink.send($0) }
    )
  }

  private func utcCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }

  private func transaction(id: String, date: Date) -> FinanceTransaction {
    FinanceTransaction(
      id: id,
      merchant: "Merchant",
      category: "Category",
      symbol: "creditcard.fill",
      date: date,
      amount: 10,
      kind: .expense
    )
  }
}

private final class ConnectionStateStub: ConnectionStateProviding {
  var isConfigured: Bool
  var hasVerifiedAPIKey: Bool

  init(isConfigured: Bool, hasVerifiedAPIKey: Bool = false) {
    self.isConfigured = isConfigured
    self.hasVerifiedAPIKey = hasVerifiedAPIKey
  }
}

private actor FinanceDataClientStub: FinanceDataClient {
  enum Call: CaseIterable, Hashable {
    case accounts
    case transactions
    case budgets
    case insights
  }

  private var accountsResult: Result<[FinanceAccount], TestFailure>
  private var transactionsResult: Result<[FinanceTransaction], TestFailure>
  private var budgetsResult: Result<[BudgetCategory], TestFailure>
  private var insightsResult: Result<[BackendInsight], TestFailure>
  private var calls: [Call] = []

  init(
    accountsResult: Result<[FinanceAccount], TestFailure> = .success([]),
    transactionsResult: Result<[FinanceTransaction], TestFailure> = .success([]),
    budgetsResult: Result<[BudgetCategory], TestFailure> = .success([]),
    insightsResult: Result<[BackendInsight], TestFailure> = .success([])
  ) {
    self.accountsResult = accountsResult
    self.transactionsResult = transactionsResult
    self.budgetsResult = budgetsResult
    self.insightsResult = insightsResult
  }

  func fetchAccounts() async throws -> [FinanceAccount] {
    calls.append(.accounts)
    return try accountsResult.get()
  }

  func fetchTransactions() async throws -> [FinanceTransaction] {
    calls.append(.transactions)
    return try transactionsResult.get()
  }

  func fetchBudgetCategories() async throws -> [BudgetCategory] {
    calls.append(.budgets)
    return try budgetsResult.get()
  }

  func fetchInsights() async throws -> [BackendInsight] {
    calls.append(.insights)
    return try insightsResult.get()
  }

  func recordedCalls() -> [Call] {
    calls
  }
}

private actor PartiallySuccessfulFinanceDataClient: FinanceDataClient {
  func fetchAccounts() async throws -> [FinanceAccount] {
    [FinanceAccount(
      id: "new-account",
      name: "New account",
      institution: "Sure",
      kind: .cash,
      balance: 200,
      change: 0,
      tintName: "teal"
    )]
  }

  func fetchTransactions() async throws -> [FinanceTransaction] { throw CancellationError() }
  func fetchBudgetCategories() async throws -> [BudgetCategory] { [] }
  func fetchInsights() async throws -> [BackendInsight] { [] }
}

@MainActor
private final class InsightSinkSpy {
  private(set) var sentInsightIDs: [[String]] = []

  func send(_ insights: [BackendInsight]) {
    sentInsightIDs.append(insights.map(\.id))
  }
}

private enum TestFailure: LocalizedError {
  case expected

  var errorDescription: String? { "Expected failure" }
}
