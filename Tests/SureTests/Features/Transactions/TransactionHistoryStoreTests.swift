import Foundation
import Testing
@testable import Sure

@MainActor
@Suite("Transaction history store")
struct TransactionHistoryStoreTests {
  @Test("Account history requests exactly 31 inclusive days for that account")
  func accountRequest() async throws {
    let accountID = try #require(UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"))
    let client = TransactionHistoryClientStub()
    let store = makeStore(
      scope: .account(id: accountID, name: "Everyday Checking"),
      client: client
    )

    await store.load()

    let requests = await client.recordedRequests()
    #expect(requests == [TransactionHistoryRequest(
      accountID: accountID,
      dateWindow: try TransactionDateWindow(
        startDate: LocalDate(year: 2026, month: 7, day: 29),
        endDate: LocalDate(year: 2026, month: 8, day: 28)
      )
    )])
    #expect(store.scope.navigationTitle == "Everyday Checking")
    #expect(store.scope.periodLabel == "Last 31 days")
  }

  @Test("Recent activity requests exactly seven inclusive days across accounts")
  func recentActivityRequest() async throws {
    let client = TransactionHistoryClientStub()
    let store = makeStore(scope: .recentActivity, client: client)

    await store.load()

    let requests = await client.recordedRequests()
    #expect(requests == [TransactionHistoryRequest(
      accountID: nil,
      dateWindow: try TransactionDateWindow(
        startDate: LocalDate(year: 2026, month: 8, day: 22),
        endDate: LocalDate(year: 2026, month: 8, day: 28)
      )
    )])
    #expect(store.scope.navigationTitle == "Recent activity")
    #expect(store.scope.periodLabel == "Last 7 days")
  }

  @Test("Loading is observable and duplicate concurrent loads are ignored")
  func loadingAndDuplicateLoad() async {
    let client = SuspendedTransactionHistoryClient()
    let store = makeStore(scope: .recentActivity, client: client)

    let load = Task { await store.load() }
    await client.waitForRequest()

    #expect(store.state == .loading)
    await store.load()
    let requestCount = await client.requestCount
    #expect(requestCount == 1)

    await client.complete(with: [])
    await load.value
    #expect(store.state == .loaded)
  }

  @Test("Successful loads sort transactions newest first with a stable tie break")
  func successfulLoad() async {
    let earlier = Date(timeIntervalSince1970: 1_700_000_000)
    let later = Date(timeIntervalSince1970: 1_700_086_400)
    let client = TransactionHistoryClientStub(outcome: .success([
      transaction(id: 2, date: later),
      transaction(id: 3, date: earlier),
      transaction(id: 1, date: later)
    ]))
    let store = makeStore(scope: .recentActivity, client: client)

    await store.load()

    #expect(store.state == .loaded)
    #expect(store.transactions.map(\.id) == [historyTestID(1), historyTestID(2), historyTestID(3)])
  }

  @Test("An empty response is a successful loaded state")
  func emptyLoad() async {
    let store = makeStore(
      scope: .account(
        id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
        name: "Everyday Checking"
      ),
      client: TransactionHistoryClientStub()
    )

    await store.load()

    #expect(store.state == .loaded)
    #expect(store.transactions.isEmpty)
    #expect(store.scope.emptyTitle == "No transactions")
    #expect(store.scope.emptyDescription == "No transactions were found for Everyday Checking in the last 31 days.")
  }

  @Test("Failures become an explicit failed state")
  func failedLoad() async {
    let store = makeStore(
      scope: .recentActivity,
      client: TransactionHistoryClientStub(outcome: .failure)
    )

    await store.load()

    #expect(store.state == .failed("Expected history failure"))
    #expect(store.transactions.isEmpty)
  }

  @Test("A failed load can be retried successfully")
  func retryAfterFailure() async {
    let client = TransactionHistoryClientStub(outcome: .failure)
    let store = makeStore(scope: .recentActivity, client: client)

    await store.load()
    await client.setOutcome(.success([
      transaction(id: 4, date: referenceDate)
    ]))
    await store.load()

    #expect(store.state == .loaded)
    #expect(store.transactions.map(\.id) == [historyTestID(4)])
  }

  @Test("Cancellation restores the previous state instead of failing")
  func cancelledLoad() async {
    let store = makeStore(
      scope: .recentActivity,
      client: TransactionHistoryClientStub(outcome: .cancelled)
    )

    await store.load()

    #expect(store.state == .idle)
    #expect(store.transactions.isEmpty)
  }

  @Test("The clock is captured once per load")
  func clockCapturedOnce() async {
    let clock = HistoryClockSpy(value: referenceDate)
    let store = TransactionHistoryStore(
      scope: .recentActivity,
      client: TransactionHistoryClientStub(),
      calendar: utcCalendar,
      now: { clock.call() }
    )

    await store.load()

    #expect(clock.callCount == 1)
  }

  @Test("The factory passes its dependencies into new stores")
  func factory() async {
    let client = TransactionHistoryClientStub()
    let clock = HistoryClockSpy(value: referenceDate)
    let factory = TransactionHistoryStoreFactory(
      client: client,
      calendar: utcCalendar,
      now: { clock.call() }
    )
    let store = factory.makeStore(for: .recentActivity)

    await store.load()

    let requests = await client.recordedRequests()
    #expect(requests.count == 1)
    #expect(clock.callCount == 1)
  }

  private func makeStore(
    scope: TransactionHistoryScope,
    client: any TransactionHistoryClient
  ) -> TransactionHistoryStore {
    TransactionHistoryStore(
      scope: scope,
      client: client,
      calendar: utcCalendar,
      now: { referenceDate }
    )
  }

  private func transaction(id: Int, date: Date) -> FinanceTransaction {
    FinanceTransaction(
      id: historyTestID(id),
      merchant: "Merchant",
      category: "Category",
      symbol: "creditcard.fill",
      date: try! LocalDate(date, in: utcCalendar),
      amount: Money(
        minorUnits: 1_000,
        currency: CurrencyCode("USD")!
      ),
      kind: .expense,
      accountID: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
    )
  }

  private var referenceDate: Date {
    utcCalendar.date(from: DateComponents(
      year: 2026,
      month: 8,
      day: 28,
      hour: 18
    ))!
  }

  private var utcCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }
}

private func historyTestID(_ value: Int) -> UUID {
  UUID(uuidString: String(
    format: "00000000-0000-4000-8000-%012d",
    value
  ))!
}

private actor TransactionHistoryClientStub: TransactionHistoryClient {
  private var requests: [TransactionHistoryRequest] = []
  private var outcome: TransactionHistoryClientOutcome

  init(outcome: TransactionHistoryClientOutcome = .success([])) {
    self.outcome = outcome
  }

  func fetchTransactions(_ request: TransactionHistoryRequest) async throws -> [FinanceTransaction] {
    requests.append(request)
    switch outcome {
    case .success(let transactions):
      return transactions
    case .failure:
      throw HistoryTestFailure.expected
    case .cancelled:
      throw CancellationError()
    }
  }

  func recordedRequests() -> [TransactionHistoryRequest] {
    requests
  }

  func setOutcome(_ outcome: TransactionHistoryClientOutcome) {
    self.outcome = outcome
  }
}

private actor SuspendedTransactionHistoryClient: TransactionHistoryClient {
  private var requests: [TransactionHistoryRequest] = []
  private var requestWaiters: [CheckedContinuation<Void, Never>] = []
  private var responseContinuation: CheckedContinuation<[FinanceTransaction], Error>?

  var requestCount: Int { requests.count }

  func fetchTransactions(_ request: TransactionHistoryRequest) async throws -> [FinanceTransaction] {
    requests.append(request)
    requestWaiters.forEach { $0.resume() }
    requestWaiters = []
    return try await withCheckedThrowingContinuation { continuation in
      responseContinuation = continuation
    }
  }

  func waitForRequest() async {
    guard requests.isEmpty else { return }
    await withCheckedContinuation { continuation in
      requestWaiters.append(continuation)
    }
  }

  func complete(with transactions: [FinanceTransaction]) {
    responseContinuation?.resume(returning: transactions)
    responseContinuation = nil
  }
}

@MainActor
private final class HistoryClockSpy {
  private(set) var callCount = 0
  private var value: Date

  init(value: Date) {
    self.value = value
  }

  func call() -> Date {
    callCount += 1
    return value
  }
}

private enum HistoryTestFailure: LocalizedError {
  case expected

  var errorDescription: String? { "Expected history failure" }
}

private enum TransactionHistoryClientOutcome {
  case success([FinanceTransaction])
  case failure
  case cancelled
}
