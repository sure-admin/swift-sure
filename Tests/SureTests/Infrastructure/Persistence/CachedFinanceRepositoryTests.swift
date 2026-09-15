import Foundation
import Testing
@testable import Sure

@Suite("Scoped server read cache")
@MainActor
struct CachedFinanceRepositoryTests {
  @Test("Network outages and entitlement suspension reopen the same complete window")
  func offlineWindow() async throws {
    let harness = Harness()
    defer { harness.cleanup() }
    let request = try harness.request()
    #expect(try await harness.repository.fetchTransactions(request) == [testReadTransaction])
    harness.client.historyFailure = URLError(.notConnectedToInternet)
    #expect(try await harness.repository.fetchTransactions(request) == [testReadTransaction])
    let metadata = await harness.repository.readMetadata(for: CachedFinanceRepository.transactionKey(request))
    #expect(metadata?.source == .cache)
    #expect(metadata?.fetchedAt == testReadDate)
    harness.gate.update(expiration: nil)
    #expect(try await harness.repository.fetchTransactions(request) == [testReadTransaction])
    #expect(harness.client.windows.count == 2)
    await #expect(throws: DataFailure.subscription) {
      _ = try await harness.repository.fetchTransactions(harness.request(day: 14))
    }
    await #expect(throws: DataFailure.subscription) {
      _ = try await harness.repository.fetchTransactions(TransactionHistoryRequest(accountID: testReadAccount.id, dateWindow: request.dateWindow))
    }
  }

  @Test("A successful empty window replaces records deleted on Sure")
  func replaceWindow() async throws {
    let harness = Harness(); defer { harness.cleanup() }
    let request = try harness.request()
    _ = try await harness.repository.fetchTransactions(request)
    harness.client.transactions = []
    _ = try await harness.repository.fetchTransactions(request)
    harness.gate.update(expiration: nil)
    #expect(try await harness.repository.fetchTransactions(request).isEmpty)
  }

  @Test("Unauthorized and malformed reads do not silently fall back to cache", arguments: [SureAPIError.unauthorized, .forbidden, .decoding, .server(500)])
  func noMaskedFailures(error: SureAPIError) async throws {
    let harness = Harness(); defer { harness.cleanup() }
    _ = try await harness.repository.fetchAccounts()
    harness.client.accountsFailure = error
    await #expect(throws: DataFailure(error)) { _ = try await harness.repository.fetchAccounts() }
  }

  @Test("Identity changes cannot read a previous user's data")
  func isolation() async throws {
    let harness = Harness(); defer { harness.cleanup() }
    _ = try await harness.repository.fetchAccounts()
    harness.connection.id = "different-user"
    harness.gate.update(expiration: nil)
    await #expect(throws: DataFailure.subscription) { _ = try await harness.repository.fetchAccounts() }
    #expect(await harness.repository.cachedSnapshot() == nil)
  }

  @Test("Cold launch restores a versioned cache without fetching the network")
  func coldLaunch() async throws {
    let harness = Harness(); defer { harness.cleanup() }
    _ = try await harness.repository.fetchAccounts()
    let relaunched = harness.makeRepository()
    let snapshot = await relaunched.cachedSnapshot()
    #expect(snapshot?.accounts == [testReadAccount])
    #expect(harness.client.accountCalls == 1)
    #expect(await relaunched.readMetadata(for: "accounts")?.source == .cache)
  }

  @Test("Logout invalidates pending writes and removes existing reads")
  func logoutRace() async throws {
    let harness = Harness(); defer { harness.cleanup() }
    _ = try await harness.repository.fetchAccounts()
    let barrier = ReadBarrier<[FinanceAccount]>()
    harness.client.accountsOperation = { await barrier.wait() }
    let task = Task { try await harness.repository.fetchAccounts() }
    await barrier.started()
    try await harness.repository.clear()
    await barrier.finish([testReadAccount])
    await #expect(throws: DataFailure.cancelled) { _ = try await task.value }
    #expect(try await harness.cache.read(scope: harness.scope, key: "accounts") == nil)
  }

  @Test("Cache write failure preserves a successful live response")
  func diskFull() async throws {
    let harness = Harness(maximumBytes: 1); defer { harness.cleanup() }
    #expect(try await harness.repository.fetchAccounts() == [testReadAccount])
    #expect(await harness.repository.readMetadata(for: "accounts")?.failure == .persistence)
  }

  @Test("Summaries persist exact decimals and remain available when suspended")
  func summary() async throws {
    let harness = Harness(); defer { harness.cleanup() }
    let expected = try summaryFixture(); harness.client.summary = expected
    _ = try await harness.repository.fetchSummary(for: expected.month)
    harness.gate.update(expiration: nil)
    let result = try await harness.repository.fetchSummary(for: expected.month)
    #expect(result == expected)
    #expect(result.spending.amount == Decimal(string: "32.345"))
    #expect(harness.client.summaryMonths.count == 1)
  }

  @Test("The last downloaded window remains accessible with its actual coverage")
  func olderWindow() async throws {
    let harness = Harness(); defer { harness.cleanup() }
    let original = try harness.request()
    _ = try await harness.repository.fetchTransactions(original)
    harness.gate.update(expiration: nil)
    let store = TransactionHistoryStore(scope: .recentActivity, client: harness.repository,
      calendar: testReadCalendar, now: { testReadDate.addingTimeInterval(86400) })
    await store.load()
    #expect(store.state == .loaded)
    #expect(store.showingDownloadedData)
    #expect(store.downloadedWindow == original.dateWindow)
    #expect(store.transactions == [testReadTransaction])
    #expect(store.metadata?.fetchedAt == testReadDate)
  }

  @Test("A response outside its requested scope cannot enter the cache")
  func invalidCoverage() async throws {
    let harness = Harness(); defer { harness.cleanup() }
    await #expect(throws: DataFailure.malformed) {
      _ = try await harness.repository.fetchTransactions(harness.request(day: 14))
    }
    #expect(await harness.repository.latestDownloadedTransactions(accountID: nil) == nil)
  }

  @Test("The store rejects writes from a lease invalidated by erasure")
  func cacheLease() async throws {
    let harness = Harness(); defer { harness.cleanup() }
    let lease = await harness.cache.lease()
    try await harness.cache.removeAll()
    await #expect(throws: CancellationError.self) {
      try await harness.cache.write(.init(fetchedAt: testReadDate, payload: Data()), scope: "one", key: "accounts", lease: lease)
    }
  }

  @MainActor
  private final class Harness {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let client = FinanceReadFake()
    let connection = ReadConnectionFake()
    let gate = BackendAccessGate(now: { testReadDate })
    let cache: ServerReadCache
    lazy var repository = makeRepository()
    let server = URL(string: "https://sure.example")!
    var scope: String { server.absoluteString + "\n" + connection.id }
    init(maximumBytes: Int = 1_000_000) {
      cache = ServerReadCache(directory: directory, maximumBytes: maximumBytes)
      gate.update(expiration: .distantFuture)
    }
    func makeRepository() -> CachedFinanceRepository {
      CachedFinanceRepository(base: client, history: client, summaries: client, cache: cache, gate: gate,
        identity: { [self] in (server, connection.id) }, now: { testReadDate })
    }
    func request(day: Int = 15) throws -> TransactionHistoryRequest {
      .init(dateWindow: try TransactionDateWindow(startDate: LocalDate(year: 2024, month: 2, day: 9),
        endDate: LocalDate(year: 2024, month: 2, day: day)))
    }
    func cleanup() { try? FileManager.default.removeItem(at: directory) }
  }
}
