import Foundation
import Testing
@testable import Sure

struct OfflineSubscriptionDataTransportTests {
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
