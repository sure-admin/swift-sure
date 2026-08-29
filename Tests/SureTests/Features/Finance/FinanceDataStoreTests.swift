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
      id: financeTestID(1),
      name: "Checking",
      institution: "Sure",
      kind: .cash,
      balance: financeTestMoney(12_500),
      tintName: "blue"
    )
    let transaction = FinanceTransaction(
      id: financeTestID(2),
      merchant: "Market",
      category: "Groceries",
      symbol: "cart.fill",
      date: financeTestDate(fixedNow),
      amount: financeTestMoney(2_500),
      kind: .expense,
      accountID: financeTestID(1)
    )
    let budget = BudgetCategory(
      id: financeTestID(3),
      name: "Groceries",
      symbol: "cart.fill",
      spent: financeTestMoney(2_500),
      limit: financeTestMoney(10_000)
    )
    let insight = BackendInsight(
      id: "insight-1",
      type: "budget_on_track",
      title: "On track",
      body: "Spending is within the plan.",
      priority: "medium",
      status: "active",
      generatedAt: fixedNow
    )
    let client = FinanceDataClientStub(
      balanceSheetResult: .success(financeTestBalanceSheet()),
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
    #expect(store.netWorth == financeTestMoney(1_000_000))
    #expect(store.accounts.map(\.id) == [financeTestID(1)])
    #expect(store.transactions.map(\.id) == [financeTestID(2)])
    #expect(store.budgets.map(\.id) == [financeTestID(3)])
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

  @Test("The authoritative balance sheet is required and never reconstructed from accounts")
  func balanceSheetFailure() async {
    let client = FinanceDataClientStub(
      balanceSheetResult: .failure(.expected),
      accountsResult: .success([
        FinanceAccount(
          id: financeTestID(4),
          name: "Foreign account",
          institution: "Sure",
          kind: .cash,
          balance: financeTestMoney(99_999, currency: "EUR"),
          tintName: "teal"
        )
      ])
    )
    let store = makeStore(
      connection: ConnectionStateStub(isConfigured: true),
      client: client,
      insightSink: InsightSinkSpy()
    )

    await store.refresh()

    #expect(store.state == .failed("Expected failure"))
    #expect(store.netWorth == nil)
    #expect(store.accounts.isEmpty)
  }

  @Test("A budget failure remains distinct from an empty budget")
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
    #expect(store.budgetError == "Expected failure")
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
    store.balanceSheet = financeTestBalanceSheet()
    store.accounts = [
      FinanceAccount(
        id: financeTestID(1),
        name: "Checking",
        institution: "Sure",
        kind: .cash,
        balance: financeTestMoney(12_500),
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
        generatedAt: nil
      )
    ]
    store.lastUpdated = Date(timeIntervalSince1970: 1_800_000_000)

    store.disconnect()

    #expect(store.accounts.isEmpty)
    #expect(store.balanceSheet == nil)
    #expect(store.transactions.isEmpty)
    #expect(store.budgets.isEmpty)
    #expect(store.budgetError == nil)
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
      transaction(id: 31, date: january31),
      transaction(id: 1, date: january1),
      transaction(id: 12, date: december31)
    ]

    #expect(store.reportingPeriodTransactions.map(\.id) == [financeTestID(31), financeTestID(1)])
  }

  @Test("Period totals remain separated by currency")
  func mixedCurrencyPeriodTotals() throws {
    let calendar = utcCalendar()
    let referenceDate = try #require(
      calendar.date(from: DateComponents(year: 2026, month: 8, day: 28, hour: 12))
    )
    let store = FinanceDataStore(
      connection: ConnectionStateStub(isConfigured: true),
      client: FinanceDataClientStub(),
      calendar: calendar,
      now: { referenceDate },
      syncInsights: { _ in }
    )
    store.transactions = [
      transaction(id: 40, date: referenceDate, minorUnits: 100_000, currency: "USD", kind: .income),
      transaction(id: 41, date: referenceDate, minorUnits: 25_000, currency: "EUR", kind: .income),
      transaction(id: 42, date: referenceDate, minorUnits: 12_500, currency: "USD", kind: .expense)
    ]

    #expect(store.periodIncome.amounts == [
      financeTestMoney(25_000, currency: "EUR"),
      financeTestMoney(100_000, currency: "USD")
    ])
    #expect(store.periodSpending.amounts == [financeTestMoney(12_500)])
    #expect(store.savingsRate == nil)
  }

  @Test("Savings rate handles same-currency empty, overspent, and zero-income periods")
  func savingsRateEdgeCases() throws {
    let calendar = utcCalendar()
    let referenceDate = try #require(
      calendar.date(from: DateComponents(year: 2026, month: 8, day: 28, hour: 12))
    )
    let store = FinanceDataStore(
      connection: ConnectionStateStub(isConfigured: true),
      client: FinanceDataClientStub(),
      calendar: calendar,
      now: { referenceDate },
      syncInsights: { _ in }
    )

    store.transactions = [
      transaction(
        id: 50,
        date: referenceDate,
        minorUnits: 100_000,
        kind: .income
      ),
      transaction(
        id: 51,
        date: referenceDate,
        minorUnits: 25_000,
        kind: .expense
      )
    ]
    #expect(store.savingsRate == Decimal(string: "0.75"))

    store.transactions = [
      transaction(
        id: 52,
        date: referenceDate,
        minorUnits: 100_000,
        kind: .income
      )
    ]
    #expect(store.savingsRate == Decimal(1))

    store.transactions = [
      transaction(
        id: 53,
        date: referenceDate,
        minorUnits: 100_000,
        kind: .income
      ),
      transaction(
        id: 54,
        date: referenceDate,
        minorUnits: 125_000,
        kind: .expense
      )
    ]
    #expect(store.savingsRate == Decimal.zero)

    store.transactions = [
      transaction(
        id: 55,
        date: referenceDate,
        minorUnits: 0,
        kind: .income
      )
    ]
    #expect(store.savingsRate == nil)
  }

  @Test("Savings rate is unavailable when spending and income currencies differ")
  func savingsRateCurrencyMismatch() throws {
    let calendar = utcCalendar()
    let referenceDate = try #require(
      calendar.date(from: DateComponents(year: 2026, month: 8, day: 28, hour: 12))
    )
    let store = FinanceDataStore(
      connection: ConnectionStateStub(isConfigured: true),
      client: FinanceDataClientStub(),
      calendar: calendar,
      now: { referenceDate },
      syncInsights: { _ in }
    )
    store.transactions = [
      transaction(
        id: 56,
        date: referenceDate,
        minorUnits: 100_000,
        currency: "USD",
        kind: .income
      ),
      transaction(
        id: 57,
        date: referenceDate,
        minorUnits: 25_000,
        currency: "EUR",
        kind: .expense
      )
    ]

    #expect(store.savingsRate == nil)
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
      transaction(id: 21, date: dayBeforeWindow),
      transaction(id: 22, date: firstIncludedDay),
      transaction(id: 29, date: tomorrow),
      transaction(id: 28, date: today)
    ]

    #expect(store.recentActivityTransactions.map(\.id) == [financeTestID(28), financeTestID(22)])
  }

  @Test("Cancellation cannot publish a partially refreshed finance snapshot")
  func cancelledRefreshIsAtomic() async {
    let previousTimestamp = Date(timeIntervalSince1970: 1_700_000_000)
    let previousBalanceSheet = financeTestBalanceSheet()
    let store = makeStore(
      connection: ConnectionStateStub(isConfigured: true),
      client: PartiallySuccessfulFinanceDataClient(),
      insightSink: InsightSinkSpy()
    )
    store.balanceSheet = previousBalanceSheet
    store.accounts = [FinanceAccount(
      id: financeTestID(10),
      name: "Previous account",
      institution: "Sure",
      kind: .cash,
      balance: financeTestMoney(10_000),
      tintName: "blue"
    )]
    store.transactions = [transaction(id: 11, date: previousTimestamp)]
    store.budgets = [BudgetCategory(
      id: financeTestID(12),
      name: "Previous budget",
      symbol: "cart.fill",
      spent: financeTestMoney(1_000),
      limit: financeTestMoney(10_000)
    )]
    store.lastUpdated = previousTimestamp
    store.state = .loaded

    await store.refresh()

    #expect(store.state == .loaded)
    #expect(store.balanceSheet == previousBalanceSheet)
    #expect(store.accounts.map(\.id) == [financeTestID(10)])
    #expect(store.transactions.map(\.id) == [financeTestID(11)])
    #expect(store.budgets.map(\.id) == [financeTestID(12)])
    #expect(store.lastUpdated == previousTimestamp)
  }

  @Test("Disconnect invalidates a refresh that finishes after the session changes")
  func disconnectInvalidatesInFlightRefresh() async {
    let connection = ConnectionStateStub(isConfigured: true)
    let client = SuspendedAccountsFinanceDataClient()
    let store = makeStore(
      connection: connection,
      client: client,
      insightSink: InsightSinkSpy()
    )
    let refresh = Task { await store.refresh() }
    await client.waitUntilStarted()

    connection.isConfigured = false
    store.disconnect()
    await client.complete()
    await refresh.value

    #expect(store.state == .needsConnection)
    #expect(store.accounts.isEmpty)
    #expect(store.transactions.isEmpty)
    #expect(store.lastUpdated == nil)
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

  private func transaction(
    id: Int,
    date: Date,
    minorUnits: Int64 = 1_000,
    currency: String = "USD",
    kind: TransactionKind = .expense
  ) -> FinanceTransaction {
    FinanceTransaction(
      id: financeTestID(id),
      merchant: "Merchant",
      category: "Category",
      symbol: "creditcard.fill",
      date: financeTestDate(date),
      amount: financeTestMoney(minorUnits, currency: currency),
      kind: kind,
      accountID: financeTestID(1)
    )
  }
}

private func financeTestID(_ value: Int) -> UUID {
  UUID(uuidString: String(
    format: "00000000-0000-4000-8000-%012d",
    value
  ))!
}

private func financeTestMoney(
  _ minorUnits: Int64,
  currency: String = "USD"
) -> Money {
  Money(
    minorUnits: minorUnits,
    currency: CurrencyCode(currency)!
  )
}

private func financeTestDate(_ date: Date) -> LocalDate {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(secondsFromGMT: 0)!
  return try! LocalDate(date, in: calendar)
}

private func financeTestBalanceSheet(
  minorUnits: Int64 = 1_000_000
) -> BalanceSheetRecord {
  let currency = CurrencyCode("USD")!
  return BalanceSheetRecord(
    currency: currency,
    netWorth: Money(minorUnits: minorUnits, currency: currency),
    assets: Money(minorUnits: minorUnits + 100_000, currency: currency),
    liabilities: Money(minorUnits: 100_000, currency: currency)
  )
}

private final class ConnectionStateStub: ConnectionStateProviding {
  var isConfigured: Bool
  var hasVerifiedAPIKey: Bool
  var sessionGeneration = 0

  init(isConfigured: Bool, hasVerifiedAPIKey: Bool = false) {
    self.isConfigured = isConfigured
    self.hasVerifiedAPIKey = hasVerifiedAPIKey
  }
}

private actor FinanceDataClientStub: FinanceDataClient {
  enum Call: CaseIterable, Hashable {
    case balanceSheet
    case accounts
    case transactions
    case budgets
    case insights
  }

  private var balanceSheetResult: Result<BalanceSheetRecord, TestFailure>
  private var accountsResult: Result<[FinanceAccount], TestFailure>
  private var transactionsResult: Result<[FinanceTransaction], TestFailure>
  private var budgetsResult: Result<[BudgetCategory], TestFailure>
  private var insightsResult: Result<[BackendInsight], TestFailure>
  private var calls: [Call] = []

  init(
    balanceSheetResult: Result<BalanceSheetRecord, TestFailure> = .success(financeTestBalanceSheet()),
    accountsResult: Result<[FinanceAccount], TestFailure> = .success([]),
    transactionsResult: Result<[FinanceTransaction], TestFailure> = .success([]),
    budgetsResult: Result<[BudgetCategory], TestFailure> = .success([]),
    insightsResult: Result<[BackendInsight], TestFailure> = .success([])
  ) {
    self.balanceSheetResult = balanceSheetResult
    self.accountsResult = accountsResult
    self.transactionsResult = transactionsResult
    self.budgetsResult = budgetsResult
    self.insightsResult = insightsResult
  }

  func fetchBalanceSheet() async throws -> BalanceSheetRecord {
    calls.append(.balanceSheet)
    return try balanceSheetResult.get()
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
  func fetchBalanceSheet() async throws -> BalanceSheetRecord {
    financeTestBalanceSheet(minorUnits: 2_000_000)
  }

  func fetchAccounts() async throws -> [FinanceAccount] {
    [FinanceAccount(
      id: financeTestID(20),
      name: "New account",
      institution: "Sure",
      kind: .cash,
      balance: financeTestMoney(20_000),
      tintName: "teal"
    )]
  }

  func fetchTransactions() async throws -> [FinanceTransaction] { throw CancellationError() }
  func fetchBudgetCategories() async throws -> [BudgetCategory] { [] }
  func fetchInsights() async throws -> [BackendInsight] { [] }
}

private actor SuspendedAccountsFinanceDataClient: FinanceDataClient {
  private var continuation: CheckedContinuation<Void, Never>?
  private var startedWaiters: [CheckedContinuation<Void, Never>] = []
  private var didStart = false

  func fetchBalanceSheet() async throws -> BalanceSheetRecord {
    financeTestBalanceSheet()
  }

  func fetchAccounts() async throws -> [FinanceAccount] {
    await withCheckedContinuation { continuation in
      self.continuation = continuation
      didStart = true
      let waiters = startedWaiters
      startedWaiters.removeAll()
      waiters.forEach { $0.resume() }
    }
    return [FinanceAccount(
      id: financeTestID(30),
      name: "Late account",
      institution: "Sure",
      kind: .cash,
      balance: financeTestMoney(10_000),
      tintName: "blue"
    )]
  }

  func fetchTransactions() async throws -> [FinanceTransaction] { [] }
  func fetchBudgetCategories() async throws -> [BudgetCategory] { [] }
  func fetchInsights() async throws -> [BackendInsight] { [] }

  func waitUntilStarted() async {
    guard !didStart else { return }
    await withCheckedContinuation { continuation in
      startedWaiters.append(continuation)
    }
  }

  func complete() {
    continuation?.resume()
    continuation = nil
  }
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
