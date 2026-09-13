import Foundation
import Testing
@testable import Sure

@Suite("Independent finance resources")
@MainActor
struct FinanceDataStoreTests {
  @Test("Overview only requests seven days and reports server summary values")
  func boundedOverview() async throws {
    let client = FinanceReadFake()
    let summary = try summaryFixture()
    client.summary = summary
    let store = makeStore(client)
    await store.refresh()
    #expect(store.state == .loaded)
    #expect(client.windows.count == 1)
    #expect(client.windows.first?.startDate.iso8601String == "2024-02-09")
    #expect(client.windows.first?.endDate.iso8601String == "2024-02-15")
    #expect(store.periodIncome == summary.income)
    #expect(store.periodSpending == summary.spending)
    #expect(store.savingsRate == summary.savingsRate)
    #expect(store.lastUpdated == testReadDate)
  }

  @Test("A suspended budget does not delay accounts")
  func independentPublication() async {
    let client = FinanceReadFake()
    let barrier = ReadBarrier<[BudgetCategory]>()
    client.budgetOperation = { await barrier.wait() }
    let store = makeStore(client)
    let task = Task { await store.refresh() }
    await barrier.started()
    while !store.accountsResource.hasValue { await Task.yield() }
    #expect(store.state == .loaded)
    #expect(store.budgetsResource.isLoading)
    #expect(store.accountsResource.metadata?.fetchedAt == testReadDate)
    await barrier.finish([])
    await task.value
  }

  @Test("A resource failure preserves its last value and timestamp")
  func partialFailure() async {
    let client = FinanceReadFake()
    let store = makeStore(client)
    await store.refresh()
    let previous = store.accountsResource.metadata
    client.accountsFailure = SureAPIError.unauthorized
    await store.refresh()
    #expect(store.state == .loaded)
    #expect(store.accountsResource.failure == .authentication)
    #expect(store.accountsResource.metadata == previous)
    #expect(store.budgetsResource.failure == nil)
  }

  @Test("Disconnect discards responses from suspended requests")
  func disconnect() async {
    let client = FinanceReadFake()
    let barrier = ReadBarrier<[FinanceAccount]>()
    client.accountsOperation = { await barrier.wait() }
    let store = makeStore(client)
    let task = Task { await store.refresh() }
    await barrier.started()
    store.disconnect()
    await barrier.finish([testReadAccount])
    await task.value
    #expect(store.state == .needsConnection)
    #expect(store.accounts.isEmpty)
    #expect(store.lastUpdated == nil)
  }

  @Test("Overlapping refreshes share work")
  func singleFlight() async {
    let client = FinanceReadFake()
    let barrier = ReadBarrier<[FinanceAccount]>()
    client.accountsOperation = { await barrier.wait() }
    let store = makeStore(client)
    let first = Task { await store.refresh() }
    await barrier.started()
    let second = Task { await store.refresh() }
    await Task.yield()
    first.cancel()
    await barrier.finish([])
    await first.value; await second.value
    #expect(client.accountCalls == 1)
    #expect(store.state == .loaded)
  }

  @Test("Month navigation fetches a summary without downloading historical transactions")
  func monthNavigation() async {
    let client = FinanceReadFake()
    let store = makeStore(client)
    await store.refresh()
    await store.selectPreviousReportingMonth()
    #expect(store.reportingDate?.iso8601String == "2024-01-01")
    #expect(client.windows.count == 1)
    #expect(client.summaryMonths.last?.start.iso8601String == "2024-01-01")
    #expect(store.currentSummary == nil)
    #expect(store.summaryResource.failure == .unavailable)
  }

  @Test("Raw transaction amounts never become authoritative monthly totals")
  func noLocalAggregation() {
    let store = makeStore(FinanceReadFake())
    store.transactions = [testReadTransaction]
    #expect(store.periodIncome == nil)
    #expect(store.periodSpending == nil)
    #expect(store.savingsRate == nil)
  }

  @Test("Gregorian month navigation ignores the device calendar system")
  func calendar() async {
    let calendar = Calendar(identifier: .buddhist)
    let store = FinanceDataStore(connection: ReadConnectionFake(), client: FinanceReadFake(),
      calendar: calendar, now: { testReadDate }, syncInsights: { _ in })
    await store.selectPreviousReportingMonth()
    #expect(store.reportingDate?.iso8601String == "2024-01-01")
  }

  @Test("An unconfigured client makes no network calls")
  func unconfigured() async {
    let client = FinanceReadFake()
    let connection = ReadConnectionFake(); connection.isConfigured = false
    let store = makeStore(client, connection: connection)
    await store.refresh()
    #expect(store.state == .needsConnection)
    #expect(client.accountCalls == 0)
  }

  private func makeStore(_ client: FinanceReadFake, connection: ReadConnectionFake? = nil) -> FinanceDataStore {
    FinanceDataStore(connection: connection ?? ReadConnectionFake(), client: client,
      calendar: testReadCalendar, now: { testReadDate }, summaries: client, syncInsights: { _ in })
  }
}
