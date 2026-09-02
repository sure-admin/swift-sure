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
    #expect(store.netWorth == financeTestDecimalMoney(1_000_000))
    #expect(store.accounts.map(\.id) == [financeTestID(1)])
    #expect(store.transactions.map(\.id) == [financeTestID(2)])
    #expect(store.budgets.map(\.id) == [financeTestID(3)])
    #expect(store.insights.map(\.id) == ["insight-1"])
    #expect(store.lastUpdated == fixedNow)
    #expect(store.balanceSheetError == nil)
    #expect(store.accountsError == nil)
    #expect(store.transactionsError == nil)
    #expect(store.budgetError == nil)
    #expect(store.insightError == nil)
    #expect(insightSink.sentInsightIDs == [["insight-1"]])
    #expect(await client.recordedTransactionWindows().map(\.startDate.iso8601String) == [
      "2026-12-16"
    ])
    #expect(await client.recordedTransactionWindows().map(\.endDate.iso8601String) == [
      "2027-01-15"
    ])
    #expect(calls.count == FinanceDataClientStub.Call.allCases.count)
    for call in FinanceDataClientStub.Call.allCases {
      #expect(calls.filter { $0 == call }.count == 1)
    }
  }

  @Test("An account failure does not hide other successful resources")
  func accountFailureIsolation() async {
    let client = FinanceDataClientStub(accountsResult: .failure(.expected))
    let store = makeStore(
      connection: ConnectionStateStub(isConfigured: true),
      client: client,
      insightSink: InsightSinkSpy()
    )

    await store.refresh()

    #expect(store.state == .loaded)
    #expect(store.accounts.isEmpty)
    #expect(store.accountsError == "Expected failure")
    #expect(store.netWorth != nil)
    #expect(store.lastUpdated == nil)
  }

  @Test("A balance-sheet failure never reconstructs net worth or hides accounts")
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

    #expect(store.state == .loaded)
    #expect(store.netWorth == nil)
    #expect(store.balanceSheetError == "Expected failure")
    #expect(store.accounts.map(\.id) == [financeTestID(4)])
  }

  @Test("A transaction failure does not hide accounts or net worth")
  func transactionFailureIsolation() async {
    let account = FinanceAccount(
      id: financeTestID(5),
      name: "Checking",
      institution: "Sure",
      kind: .cash,
      balance: financeTestMoney(10_000),
      tintName: "blue"
    )
    let client = FinanceDataClientStub(
      accountsResult: .success([account]),
      transactionsResult: .failure(.expected)
    )
    let store = makeStore(
      connection: ConnectionStateStub(isConfigured: true),
      client: client,
      insightSink: InsightSinkSpy()
    )

    await store.refresh()

    #expect(store.state == .loaded)
    #expect(store.netWorth != nil)
    #expect(store.accounts.map(\.id) == [financeTestID(5)])
    #expect(store.transactions.isEmpty)
    #expect(store.transactionsError == "Expected failure")
  }

  @Test("The store fails globally only when every resource fails")
  func totalFailure() async {
    let client = FinanceDataClientStub(
      balanceSheetResult: .failure(.expected),
      accountsResult: .failure(.expected),
      transactionsResult: .failure(.expected),
      budgetsResult: .failure(.expected),
      insightsResult: .failure(.expected)
    )
    let store = makeStore(
      connection: ConnectionStateStub(isConfigured: true),
      client: client,
      insightSink: InsightSinkSpy()
    )

    await store.refresh()

    #expect(store.state == .failed("Expected failure"))
    #expect(store.lastUpdated == nil)
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
    #expect(insightSink.sentInsightIDs.isEmpty)
  }

  @Test("An insight failure does not make cached Watch data appear fresh")
  func cachedInsightsAreNotResyncedAfterFailure() async {
    let insight = BackendInsight(
      id: "insight-cached",
      type: "budget_on_track",
      title: "On track",
      body: "Spending is within the plan.",
      priority: "medium",
      status: "active",
      generatedAt: nil
    )
    let client = FinanceDataClientStub(insightsResult: .success([insight]))
    let insightSink = InsightSinkSpy()
    let store = makeStore(
      connection: ConnectionStateStub(isConfigured: true),
      client: client,
      insightSink: insightSink
    )
    await store.refresh()
    await client.setInsightsResult(.failure(.expected))

    await store.refresh()

    #expect(store.insights.map(\.id) == ["insight-cached"])
    #expect(store.insightError == "Expected failure")
    #expect(insightSink.sentInsightIDs == [["insight-cached"]])
  }

  @Test("A protected snapshot restores the complete Overview synchronously")
  func cachedOverviewRestoresAtLaunch() async throws {
    let serverURL = try #require(URL(string: "https://sure.example"))
    let snapshot = financeTestSnapshot(serverURL: serverURL)
    let cache = FinanceDataSnapshotCacheSpy(
      data: try FinanceDataSnapshotCodec().encode(snapshot)
    )
    let client = FinanceDataClientStub()
    let insightSink = InsightSinkSpy()

    let store = makeStore(
      connection: ConnectionStateStub(isConfigured: true),
      client: client,
      insightSink: insightSink,
      snapshotCache: cache,
      snapshotServerURL: { serverURL }
    )

    #expect(store.state == .loaded)
    #expect(store.balanceSheet?.netWorth == snapshot.balanceSheet?.netWorth)
    #expect(store.accounts.map(\.id) == snapshot.accounts.map(\.id))
    #expect(store.transactions.map(\.id) == snapshot.transactions.map(\.id))
    #expect(store.budgets.map(\.id) == snapshot.budgets.map(\.id))
    #expect(store.insights.map(\.id) == ["cached-insight"])
    #expect(store.lastUpdated == snapshot.lastUpdated)
    #expect(await client.recordedCalls().isEmpty)
    #expect(insightSink.sentInsightIDs.isEmpty)
  }

  @Test("An unreadable snapshot is removed and treated as a first launch")
  func malformedOverviewSnapshotIsDiscarded() {
    let cache = FinanceDataSnapshotCacheSpy(data: Data("not-json".utf8))
    let store = makeStore(
      connection: ConnectionStateStub(isConfigured: true),
      client: FinanceDataClientStub(),
      insightSink: InsightSinkSpy(),
      snapshotCache: cache,
      snapshotServerURL: { URL(string: "https://sure.example") }
    )

    #expect(store.state == .idle)
    #expect(cache.data == nil)
    #expect(cache.removeCount == 1)
  }

  @Test("A snapshot for another connection identity is never displayed")
  func mismatchedOverviewIdentityIsDiscarded() throws {
    let serverURL = try #require(URL(string: "https://sure.example"))
    let cache = FinanceDataSnapshotCacheSpy(
      data: try FinanceDataSnapshotCodec().encode(
        financeTestSnapshot(serverURL: serverURL)
      )
    )
    let store = makeStore(
      connection: ConnectionStateStub(isConfigured: true),
      client: FinanceDataClientStub(),
      insightSink: InsightSinkSpy(),
      snapshotCache: cache,
      snapshotServerURL: { serverURL },
      snapshotConnectionIdentity: { "another-account" }
    )

    #expect(store.state == .idle)
    #expect(store.insights.isEmpty)
    #expect(cache.data == nil)
    #expect(cache.removeCount == 1)
  }

  @Test("A transient snapshot read failure preserves the last-good file")
  func snapshotReadFailureDoesNotDeleteCache() throws {
    let serverURL = try #require(URL(string: "https://sure.example"))
    let cachedData = try FinanceDataSnapshotCodec().encode(
      financeTestSnapshot(serverURL: serverURL)
    )
    let cache = FinanceDataSnapshotCacheSpy(
      data: cachedData,
      loadError: .expected
    )

    let store = makeStore(
      connection: ConnectionStateStub(isConfigured: true),
      client: FinanceDataClientStub(),
      insightSink: InsightSinkSpy(),
      snapshotCache: cache,
      snapshotServerURL: { serverURL }
    )

    #expect(store.state == .idle)
    #expect(cache.data == cachedData)
    #expect(cache.removeCount == 0)
  }

  @Test("A failed connection change can restore the previous cached Overview")
  func connectionChangeRollbackRestoresCache() async throws {
    let serverURL = try #require(URL(string: "https://sure.example"))
    let cache = FinanceDataSnapshotCacheSpy(
      data: try FinanceDataSnapshotCodec().encode(
        financeTestSnapshot(serverURL: serverURL)
      )
    )
    let client = FinanceDataClientStub(
      balanceSheetResult: .failure(.expected),
      accountsResult: .failure(.expected),
      transactionsResult: .failure(.expected),
      budgetsResult: .failure(.expected),
      insightsResult: .failure(.expected)
    )
    let store = makeStore(
      connection: ConnectionStateStub(isConfigured: true),
      client: client,
      insightSink: InsightSinkSpy(),
      snapshotCache: cache,
      snapshotServerURL: { serverURL }
    )
    let lifecycle = ApplicationConnectionLifecycle()
    lifecycle.financeData = store

    await lifecycle.prepareForConnectionChange()
    #expect(store.state == .needsConnection)
    #expect(cache.data != nil)

    await lifecycle.didConnect()
    #expect(store.state == .loaded)
    #expect(store.insights.map(\.id) == ["cached-insight"])

    lifecycle.didCommitConnectionChange()
    #expect(cache.data == nil)
  }

  @Test("The protected file cache round-trips and removes snapshot data")
  func protectedFileCacheRoundTrip() throws {
    let fileManager = FileManager.default
    let directoryURL = fileManager.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? fileManager.removeItem(at: directoryURL) }
    let cache = FileFinanceDataSnapshotCache(
      fileManager: fileManager,
      applicationSupportURL: directoryURL,
      bundleIdentifier: "FinanceDataStoreTests"
    )
    let expected = Data("protected snapshot".utf8)

    try cache.saveSnapshotData(expected)
    #expect(try cache.loadSnapshotData() == expected)

    try cache.removeSnapshotData()
    #expect(try cache.loadSnapshotData() == nil)
  }

  @Test("A hydrated Overview remains visible while it refreshes in the background")
  func cachedOverviewRemainsVisibleDuringRefresh() async throws {
    let serverURL = try #require(URL(string: "https://sure.example"))
    let cache = FinanceDataSnapshotCacheSpy(
      data: try FinanceDataSnapshotCodec().encode(
        financeTestSnapshot(serverURL: serverURL)
      )
    )
    let client = SuspendedAccountsFinanceDataClient()
    let store = makeStore(
      connection: ConnectionStateStub(isConfigured: true),
      client: client,
      insightSink: InsightSinkSpy(),
      snapshotCache: cache,
      snapshotServerURL: { serverURL }
    )

    let refresh = Task { @MainActor in await store.refreshIfNeeded() }
    await client.waitUntilStarted()

    #expect(store.state == .loaded)
    #expect(store.insights.map(\.id) == ["cached-insight"])
    #expect(store.isLoadingInsights)

    await client.complete()
    await refresh.value
    #expect(store.state == .loaded)
    #expect(store.insights.isEmpty)
  }

  @Test("A live refresh persists an Overview that the next store restores")
  func refreshPersistsOverview() async throws {
    let serverURL = try #require(URL(string: "https://sure.example"))
    let insight = BackendInsight(
      id: "fresh-insight",
      type: "budget_on_track",
      title: "On track",
      body: "Spending is within the plan.",
      priority: "medium",
      status: "active",
      generatedAt: nil
    )
    let cache = FinanceDataSnapshotCacheSpy()
    let firstStore = makeStore(
      connection: ConnectionStateStub(isConfigured: true),
      client: FinanceDataClientStub(insightsResult: .success([insight])),
      insightSink: InsightSinkSpy(),
      snapshotCache: cache,
      snapshotServerURL: { serverURL }
    )

    await firstStore.refresh()
    let savedData = try #require(cache.data)
    #expect(cache.saveCount == 1)

    let secondInsightSink = InsightSinkSpy()
    let secondStore = makeStore(
      connection: ConnectionStateStub(isConfigured: true),
      client: FinanceDataClientStub(),
      insightSink: secondInsightSink,
      snapshotCache: FinanceDataSnapshotCacheSpy(data: savedData),
      snapshotServerURL: { serverURL }
    )
    #expect(secondStore.state == .loaded)
    #expect(secondStore.insights.map(\.id) == ["fresh-insight"])
    #expect(secondInsightSink.sentInsightIDs.isEmpty)
  }

  @Test("A failed background refresh preserves cached data until disconnect")
  func cachedOverviewSurvivesFailureAndClearsOnDisconnect() async throws {
    let serverURL = try #require(URL(string: "https://sure.example"))
    let cache = FinanceDataSnapshotCacheSpy(
      data: try FinanceDataSnapshotCodec().encode(
        financeTestSnapshot(serverURL: serverURL)
      )
    )
    let client = FinanceDataClientStub(
      balanceSheetResult: .failure(.expected),
      accountsResult: .failure(.expected),
      transactionsResult: .failure(.expected),
      budgetsResult: .failure(.expected),
      insightsResult: .failure(.expected)
    )
    let store = makeStore(
      connection: ConnectionStateStub(isConfigured: true),
      client: client,
      insightSink: InsightSinkSpy(),
      snapshotCache: cache,
      snapshotServerURL: { serverURL }
    )

    await store.refreshIfNeeded()

    #expect(store.state == .loaded)
    #expect(store.insights.map(\.id) == ["cached-insight"])
    #expect(store.insightError == "Expected failure")

    store.disconnect()
    #expect(store.state == .needsConnection)
    #expect(store.insights.isEmpty)
    #expect(cache.removeCount == 1)
    #expect(cache.data == nil)
  }

  @Test("A partial refresh preserves cached data and its prior timestamp")
  func partialRefreshPreservesFreshness() async {
    let previousTimestamp = Date(timeIntervalSince1970: 1_700_000_000)
    let cachedAccount = FinanceAccount(
      id: financeTestID(6),
      name: "Cached account",
      institution: "Sure",
      kind: .cash,
      balance: financeTestMoney(25_000),
      tintName: "blue"
    )
    let client = FinanceDataClientStub(accountsResult: .failure(.expected))
    let store = makeStore(
      connection: ConnectionStateStub(isConfigured: true),
      client: client,
      insightSink: InsightSinkSpy()
    )
    store.accounts = [cachedAccount]
    store.lastUpdated = previousTimestamp
    store.state = .loaded

    await store.refresh()

    #expect(store.state == .loaded)
    #expect(store.accounts.map(\.id) == [cachedAccount.id])
    #expect(store.accountsError == "Expected failure")
    #expect(store.lastUpdated == previousTimestamp)
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
    #expect(store.balanceSheetError == nil)
    #expect(store.accountsError == nil)
    #expect(store.transactions.isEmpty)
    #expect(store.transactionsError == nil)
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

  @Test("The previous month is selected through the third day of a new month")
  func earlyMonthReportingPeriod() throws {
    let calendar = utcCalendar()
    let february2 = try #require(
      calendar.date(from: DateComponents(year: 2026, month: 2, day: 2, hour: 12))
    )
    let january31 = try #require(
      calendar.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 12))
    )
    let store = FinanceDataStore(
      connection: ConnectionStateStub(isConfigured: true),
      client: FinanceDataClientStub(),
      calendar: calendar,
      now: { february2 },
      syncInsights: { _ in }
    )
    store.transactions = [transaction(id: 31, date: january31)]
    let reportingDate = try LocalDate(year: 2026, month: 1, day: 1)

    #expect(store.reportingDate == reportingDate)
    #expect(store.reportingPeriodTransactions.map(\.id) == [financeTestID(31)])
    #expect(store.canSelectNextReportingMonth)
  }

  @Test("Month navigation loads complete months and does not move beyond the current month")
  func reportingPeriodNavigation() async throws {
    let calendar = utcCalendar()
    let august28 = try #require(
      calendar.date(from: DateComponents(year: 2026, month: 8, day: 28, hour: 12))
    )
    let julyTransaction = transaction(
      id: 7,
      date: try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 1)))
    )
    let client = FinanceDataClientStub(transactionsResult: .success([julyTransaction]))
    let store = FinanceDataStore(
      connection: ConnectionStateStub(isConfigured: true),
      client: client,
      calendar: calendar,
      now: { august28 },
      syncInsights: { _ in }
    )

    await store.selectPreviousReportingMonth()

    #expect(store.reportingDate == (try LocalDate(year: 2026, month: 7, day: 28)))
    #expect(store.reportingPeriodTransactions.map(\.id) == [financeTestID(7)])
    #expect(store.canSelectNextReportingMonth)

    await store.selectNextReportingMonth()
    #expect(store.reportingDate == (try LocalDate(year: 2026, month: 8, day: 28)))
    #expect(!store.canSelectNextReportingMonth)

    await store.selectNextReportingMonth()
    #expect(store.reportingDate == (try LocalDate(year: 2026, month: 8, day: 28)))
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

  @Test("A shared refresh survives cancellation of its initiating caller")
  func overlappingRefreshesAreSingleFlight() async {
    let client = OverlappingFinanceDataClient()
    let store = makeStore(
      connection: ConnectionStateStub(isConfigured: true),
      client: client,
      insightSink: InsightSinkSpy()
    )
    let firstRefresh = Task { @MainActor in await store.refresh() }
    await client.waitUntilFirstInsightsRequest()

    let callerEntry = RefreshCallerEntry()
    let overlappingRefresh = Task { @MainActor in
      callerEntry.enter()
      await store.refresh()
    }
    await callerEntry.waitUntilEntered()

    firstRefresh.cancel()
    await client.completeFirstInsightsRequest()
    await firstRefresh.value
    await overlappingRefresh.value

    let calls = await client.recordedCalls()
    #expect(store.state == .loaded)
    #expect(store.insights.map(\.id) == ["insight-overlap"])
    #expect(calls.count == FinanceDataClientStub.Call.allCases.count)
    for call in FinanceDataClientStub.Call.allCases {
      #expect(calls.filter { $0 == call }.count == 1)
    }
  }

  private func makeStore(
    connection: any ConnectionStateProviding,
    client: any FinanceDataClient,
    insightSink: InsightSinkSpy,
    now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_800_000_000) },
    snapshotCache: (any FinanceDataSnapshotCaching)? = nil,
    snapshotServerURL: @escaping () -> URL? = { nil },
    snapshotConnectionIdentity: @escaping () -> String? = { "test-identity" }
  ) -> FinanceDataStore {
    FinanceDataStore(
      connection: connection,
      client: client,
      calendar: utcCalendar(),
      now: now,
      syncInsights: { insightSink.send($0) },
      snapshotCache: snapshotCache,
      snapshotServerURL: snapshotServerURL,
      snapshotConnectionIdentity: snapshotConnectionIdentity
    )
  }

  private func financeTestSnapshot(serverURL: URL) -> FinanceDataSnapshot {
    let updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
    return FinanceDataSnapshot(
      serverURL: serverURL,
      connectionIdentity: "test-identity",
      balanceSheet: financeTestBalanceSheet(),
      accounts: [FinanceAccount(
        id: financeTestID(71),
        name: "Cached checking",
        institution: "Sure",
        kind: .cash,
        balance: financeTestMoney(125_000),
        tintName: "blue"
      )],
      transactions: [transaction(id: 72, date: updatedAt)],
      budgets: [BudgetCategory(
        id: financeTestID(73),
        name: "Cached groceries",
        symbol: "cart.fill",
        spent: financeTestMoney(2_500),
        limit: financeTestMoney(10_000)
      )],
      insights: [BackendInsight(
        id: "cached-insight",
        type: "budget_on_track",
        title: "Still on track",
        body: "This insight was restored locally.",
        priority: "medium",
        status: "active",
        generatedAt: updatedAt
      )],
      lastUpdated: updatedAt
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
    netWorth: financeTestDecimalMoney(minorUnits),
    assets: financeTestDecimalMoney(minorUnits + 100_000),
    liabilities: financeTestDecimalMoney(100_000)
  )
}

private func financeTestDecimalMoney(
  _ minorUnits: Int64,
  currency: String = "USD"
) -> DecimalMoney {
  let currencyCode = CurrencyCode(currency)!
  return DecimalMoney(
    amount: Decimal(minorUnits) / Decimal(currencyCode.minorUnitConversion),
    currency: currencyCode
  )
}

private final class ConnectionStateStub: ConnectionStateProviding {
  var isConfigured: Bool
  var sessionGeneration = 0

  init(isConfigured: Bool) {
    self.isConfigured = isConfigured
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
  private var transactionWindows: [TransactionDateWindow] = []

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

  func fetchTransactions(
    in dateWindow: TransactionDateWindow
  ) async throws -> [FinanceTransaction] {
    calls.append(.transactions)
    transactionWindows.append(dateWindow)
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

  func recordedTransactionWindows() -> [TransactionDateWindow] {
    transactionWindows
  }

  func setInsightsResult(_ result: Result<[BackendInsight], TestFailure>) {
    insightsResult = result
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

  func fetchTransactions(
    in dateWindow: TransactionDateWindow
  ) async throws -> [FinanceTransaction] {
    throw CancellationError()
  }
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

  func fetchTransactions(
    in dateWindow: TransactionDateWindow
  ) async throws -> [FinanceTransaction] { [] }
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

private actor OverlappingFinanceDataClient: FinanceDataClient {
  private var calls: [FinanceDataClientStub.Call] = []
  private var insightsRequestCount = 0
  private var firstInsightsContinuation: CheckedContinuation<Void, Never>?
  private var firstInsightsWaiters: [CheckedContinuation<Void, Never>] = []

  func fetchBalanceSheet() async throws -> BalanceSheetRecord {
    calls.append(.balanceSheet)
    return financeTestBalanceSheet()
  }

  func fetchAccounts() async throws -> [FinanceAccount] {
    calls.append(.accounts)
    return []
  }

  func fetchTransactions(
    in dateWindow: TransactionDateWindow
  ) async throws -> [FinanceTransaction] {
    calls.append(.transactions)
    return []
  }

  func fetchBudgetCategories() async throws -> [BudgetCategory] {
    calls.append(.budgets)
    return []
  }

  func fetchInsights() async throws -> [BackendInsight] {
    calls.append(.insights)
    insightsRequestCount += 1
    guard insightsRequestCount == 1 else { return [] }
    let waiters = firstInsightsWaiters
    firstInsightsWaiters.removeAll()
    waiters.forEach { $0.resume() }
    await withCheckedContinuation { continuation in
      firstInsightsContinuation = continuation
    }
    return [BackendInsight(
      id: "insight-overlap",
      type: "budget_on_track",
      title: "On track",
      body: "Spending is within the plan.",
      priority: "medium",
      status: "active",
      generatedAt: nil
    )]
  }

  func waitUntilFirstInsightsRequest() async {
    guard insightsRequestCount == 0 else { return }
    await withCheckedContinuation { continuation in
      firstInsightsWaiters.append(continuation)
    }
  }

  func completeFirstInsightsRequest() {
    firstInsightsContinuation?.resume()
    firstInsightsContinuation = nil
  }

  func recordedCalls() -> [FinanceDataClientStub.Call] {
    calls
  }
}

@MainActor
private final class RefreshCallerEntry {
  private var didEnter = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func enter() {
    didEnter = true
    let waiters = waiters
    self.waiters.removeAll()
    waiters.forEach { $0.resume() }
  }

  func waitUntilEntered() async {
    guard !didEnter else { return }
    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }
}

@MainActor
private final class InsightSinkSpy {
  private(set) var sentInsightIDs: [[String]] = []

  func send(_ insights: [BackendInsight]) {
    sentInsightIDs.append(insights.map(\.id))
  }
}

@MainActor
private final class FinanceDataSnapshotCacheSpy: FinanceDataSnapshotCaching {
  var data: Data?
  var loadError: TestFailure?
  private(set) var saveCount = 0
  private(set) var removeCount = 0

  init(data: Data? = nil, loadError: TestFailure? = nil) {
    self.data = data
    self.loadError = loadError
  }

  func loadSnapshotData() throws -> Data? {
    if let loadError { throw loadError }
    return data
  }

  func saveSnapshotData(_ data: Data) throws {
    self.data = data
    saveCount += 1
  }

  func removeSnapshotData() throws {
    data = nil
    removeCount += 1
  }
}

private enum TestFailure: LocalizedError {
  case expected

  var errorDescription: String? { "Expected failure" }
}
