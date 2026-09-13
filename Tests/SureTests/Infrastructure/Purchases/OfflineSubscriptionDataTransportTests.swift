import Foundation
import Testing
@testable import Sure

struct OfflineSubscriptionDataTransportTests {
  @Test func revocationDuringIdentityCheckRejectsResponseBeforeCaching() async throws {
    let gate = entitledTestGate()
    let cache = RevokingResponseStore(gate: nil)
    let identity = RevokingIdentity(gate: gate)
    let base = HTTPDataTransportStub([try .http(json: "{}")])
    let transport = OfflineSubscriptionDataTransport(
      base: base, gate: gate, cache: cache, identity: { await identity.get() }
    )
    let request = URLRequest(url: URL(string: "https://sure.example/accounts")!)
    await #expect(throws: BackendAccessError.self) { try await transport.data(for: request) }
    #expect(await cache.writeCount == 0)
  }

  @Test func revocationDuringCacheWriteRejectsLiveResponse() async throws {
    let gate = entitledTestGate()
    let cache = RevokingResponseStore(gate: gate)
    let base = HTTPDataTransportStub([try .http(json: "{}")])
    let transport = OfflineSubscriptionDataTransport(
      base: base, gate: gate, cache: cache, identity: { "account-a" }
    )
    let request = URLRequest(url: URL(string: "https://sure.example/accounts")!)
    await #expect(throws: BackendAccessError.self) { try await transport.data(for: request) }
    #expect(await cache.writeCount == 1)
  }

  @MainActor
  @Test func revocationDuringArchiveWriteRejectsLiveTransactions() async throws {
    let gate = entitledTestGate()
    let archive = RevokingResponseStore(gate: gate)
    let client = ArchivedTransactionHistoryClient(
      base: EmptyHistoryClient(), gate: gate, archive: archive,
      identity: { (URL(string: "https://sure.example")!, "account-a") },
      now: { Date(timeIntervalSince1970: 100) }
    )
    let request = TransactionHistoryRequest(accountID: nil, dateWindow: try TransactionDateWindow(
      startDate: LocalDate(year: 2026, month: 7, day: 1),
      endDate: LocalDate(year: 2026, month: 7, day: 31)
    ))
    await #expect(throws: BackendAccessError.self) { try await client.fetchTransactions(request) }
    #expect(await archive.writeCount == 1)
  }

  @Test func downloadedResponseSurvivesRelaunchWithoutBackendAccess() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let gate = entitledTestGate()
    let base = HTTPDataTransportStub([try .http(json: "{\"saved\":true}")])
    let request = URLRequest(url: URL(string: "https://sure.example/api/v1/chats?page=1")!)
    let online = OfflineSubscriptionDataTransport(base: SubscriptionHTTPDataTransport(base: base, gate: gate),
      gate: gate, cache: OfflineAPIResponseStore(directory: directory), identity: { "account-a" })
    let downloaded = try await online.data(for: request).0
    gate.update(expiration: nil)
    let offline = OfflineSubscriptionDataTransport(base: SubscriptionHTTPDataTransport(base: base, gate: gate),
      gate: gate, cache: OfflineAPIResponseStore(directory: directory), identity: { "account-a" })
    let reopened = try await offline.data(for: request).0
    #expect(downloaded == reopened)
    #expect(await base.requests().count == 1)
    let otherAccount = OfflineSubscriptionDataTransport(base: SubscriptionHTTPDataTransport(base: base, gate: gate),
      gate: gate, cache: OfflineAPIResponseStore(directory: directory), identity: { "account-b" })
    await #expect(throws: BackendAccessError.self) { try await otherAccount.data(for: request) }
    var upload = request
    upload.httpMethod = "POST"
    await #expect(throws: BackendAccessError.self) { try await offline.data(for: upload) }
    #expect(await base.requests().count == 1)
  }

  @Test func removingLocalDataPreventsOfflineReplay() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = OfflineAPIResponseStore(directory: directory)
    try await cache.write(Data("test".utf8), key: "account-a")
    try await cache.removeAll()
    #expect(try await cache.read(key: "account-a") == nil)
  }
}

private actor RevokingResponseStore: OfflineResponseStoring {
  var gate: BackendAccessGate?
  private(set) var writeCount = 0
  init(gate: BackendAccessGate?) { self.gate = gate }
  func read(key: String) -> Data? { nil }
  func write(_ data: Data, key: String) {
    writeCount += 1
    gate?.update(expiration: nil)
  }
  func removeAll() { }
}

private actor RevokingIdentity {
  var gate: BackendAccessGate
  var calls = 0
  init(gate: BackendAccessGate) { self.gate = gate }
  func get() -> String {
    calls += 1
    if calls == 2 { gate.update(expiration: nil) }
    return "account-a"
  }
}

private struct EmptyHistoryClient: TransactionHistoryClient {
  func fetchTransactions(_ request: TransactionHistoryRequest) async throws -> [FinanceTransaction] { [] }
}
