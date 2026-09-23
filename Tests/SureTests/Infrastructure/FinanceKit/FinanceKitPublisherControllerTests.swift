import Foundation
import Testing
@testable import Sure

@Suite("FinanceKit publisher lifecycle")
struct FinanceKitPublisherControllerTests {
  @Test("Remote disconnect failure still deletes credentials, checkpoint and pending state")
  func remoteFailureClearsLocalData() async throws {
    let environment = environment()
    defer { try? FileManager.default.removeItem(at: environment.stateURL.deletingLastPathComponent()) }
    let credentials = PublisherCredentials()
    let store = FinanceKitPublisherStateFileStore(fileURL: environment.stateURL)
    var state = FinanceKitPublisherState.empty
    state.configuration = try configuration()
    state.checkpoint = Data("private-checkpoint".utf8)
    try await store.save(state)
    let controller = FinanceKitPublisherController(gate: BackendAccessGate(), makeEnvironment: { environment },
      makeCredentialStore: { _ in credentials }, remoteDisconnect: { _ in
        #expect(try await store.load() == .empty)
        #expect(credentials.isEmpty)
        throw URLError(.notConnectedToInternet)
      })
    #expect(await controller.configuredConnectionID() == state.configuration?.connectionID)
    await #expect(throws: URLError.self) { try await controller.disconnect() }
    #expect(credentials.isEmpty)
    #expect(try await store.load() == .empty)
    #expect(await controller.configuredConnectionID() == nil)
  }

  @Test("An unreadable state does not prevent deletion of local financial records")
  func corruptStateIsDeleted() async throws {
    let environment = environment()
    defer { try? FileManager.default.removeItem(at: environment.stateURL.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(at: environment.stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("invalid-json".utf8).write(to: environment.stateURL)
    let credentials = PublisherCredentials()
    let controller = FinanceKitPublisherController(gate: BackendAccessGate(), makeEnvironment: { environment },
      makeCredentialStore: { _ in credentials })
    await #expect(throws: FinanceKitSyncError.invalidState) { try await controller.disconnect() }
    #expect(credentials.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: environment.stateURL.path))
  }

  @Test("A failed marker write synchronously invalidates the shared credential")
  func markerFailureInvalidatesCredential() throws {
    var environment = environment()
    let folder = environment.stateURL.deletingLastPathComponent()
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let obstruction = folder.appendingPathComponent("not-a-directory")
    try Data().write(to: obstruction)
    environment.revocationURL = obstruction.appendingPathComponent("revoked")
    let fixedEnvironment = environment
    let credentials = PublisherCredentials()
    let controller = FinanceKitPublisherController(gate: BackendAccessGate(), makeEnvironment: { fixedEnvironment },
      makeCredentialStore: { _ in credentials })
    try controller.blockBackgroundDelivery()
    #expect(credentials.isEmpty)
    #expect(!FinanceKitPublisherRevocationStore(fileURL: environment.revocationURL).isRevoked)
  }

  @Test("Revoked configuration never becomes an active connection after relaunch")
  func revokedConfigurationIsHidden() async throws {
    let environment = environment()
    defer { try? FileManager.default.removeItem(at: environment.stateURL.deletingLastPathComponent()) }
    var state = FinanceKitPublisherState.empty
    state.configuration = try configuration()
    state.requiresRepair = true
    try await FinanceKitPublisherStateFileStore(fileURL: environment.stateURL).save(state)
    let credentials = PublisherCredentials()
    let controller = FinanceKitPublisherController(gate: BackendAccessGate(), makeEnvironment: { environment },
      makeCredentialStore: { _ in credentials })
    #expect(await controller.requiresRepair())
    try controller.blockBackgroundDelivery()
    #expect(await controller.configuredConnectionID() == nil)
  }

  @Test("Rotation locks uploads before contacting Sure and preserves the pending stream")
  func renewalIsExclusive() async throws {
    let environment = environment()
    defer { try? FileManager.default.removeItem(at: environment.stateURL.deletingLastPathComponent()) }
    let configuration = try configuration()
    let state = pendingState(configuration)
    let store = FinanceKitPublisherStateFileStore(fileURL: environment.stateURL)
    try await store.save(state)
    let credentials = PublisherCredentials()
    let barrier = PublisherRotationBarrier()
    let gate = BackendAccessGate()
    gate.update(expiration: .distantFuture)
    let controller = FinanceKitPublisherController(gate: gate, makeEnvironment: { environment },
      makeCredentialStore: { _ in credentials }, remoteRenew: { connectionID in
        #expect(connectionID == configuration.connectionID)
        await barrier.wait()
        return (configuration, "rotated-publisher-secret")
      })
    let renewal = Task { try await controller.renewCredential() }
    await barrier.waitUntilStarted()
    await #expect(throws: FinanceKitProcessLockError.self) { try await controller.renewCredential() }
    #expect(throws: FinanceKitProcessLockError.self) { try FinanceKitProcessLock(url: environment.lockURL).acquire() }
    #expect(await barrier.calls == 1)
    await barrier.resume()
    try await renewal.value
    #expect(try await store.load() == state)
    #expect(try credentials.credential(for: configuration.publisherID) == "rotated-publisher-secret")
  }

  @Test("An active upload prevents remote credential rotation")
  func busyUploadPreventsRotation() async throws {
    let environment = environment()
    defer { try? FileManager.default.removeItem(at: environment.stateURL.deletingLastPathComponent()) }
    let gate = BackendAccessGate()
    gate.update(expiration: .distantFuture)
    let controller = FinanceKitPublisherController(gate: gate, makeEnvironment: { environment }, remoteRenew: { _ in
      Issue.record("Must not invalidate the credential during an upload")
      throw FinanceKitSyncError.invalidState
    })
    let uploadLock = try FinanceKitProcessLock(url: environment.lockURL).acquire()
    defer { _ = uploadLock }
    await #expect(throws: FinanceKitProcessLockError.self) { try await controller.renewCredential() }
    await #expect(throws: FinanceKitProcessLockError.self) { try await controller.repair() }
  }

  @Test("A rejected batch is retried unchanged with the renewed credential after relaunch")
  func renewalReplaysExactBatch() async throws {
    let environment = environment()
    defer { try? FileManager.default.removeItem(at: environment.stateURL.deletingLastPathComponent()) }
    let configuration = try configuration()
    let state = pendingState(configuration)
    let store = FinanceKitPublisherStateFileStore(fileURL: environment.stateURL)
    try await store.save(state)
    let credentials = PublisherCredentials()
    let gate = BackendAccessGate()
    gate.update(expiration: .distantFuture)
    let controller = FinanceKitPublisherController(gate: gate, makeEnvironment: { environment },
      makeCredentialStore: { _ in credentials }, remoteRenew: { _ in (configuration, "new-publisher-secret") })
    let transport = HTTPDataTransportStub([
      try .http(fixture: "financekit-publisher-unauthorized", status: 401),
      try .http(fixture: "financekit-receipt-accepted", status: 202),
      try .http(fixture: "financekit-receipt-applied")
    ])
    let engine = FinanceKitSyncEngine(stateStore: store, collector: UnexpectedPublisherCollector(),
      makeUploader: { current in
        #expect(current == configuration)
        #expect(throws: FinanceKitProcessLockError.self) { try FinanceKitProcessLock(url: environment.lockURL).acquire() }
        return FinanceKitHTTPBatchUploader(dataTransport: transport,
          credential: try #require(try credentials.credential(for: current.publisherID)), waitBeforeStatusRetry: { _ in })
      }, processLock: FinanceKitProcessLock(url: environment.lockURL))
    await #expect(throws: FinanceKitBatchUploadError.publisherUnauthorized) { try await engine.synchronize() }
    try await controller.renewCredential()
    // Reload from disk as a restarted process would; renewal must retain bytes.
    #expect(try await FinanceKitPublisherStateFileStore(fileURL: environment.stateURL).load() == state)
    #expect(try await engine.synchronize() == .uploaded(1))
    let requests = await transport.requests()
    #expect(requests.map { $0.value(forHTTPHeaderField: "Authorization") } == [
      "Bearer test-only", "Bearer new-publisher-secret", "Bearer new-publisher-secret"
    ])
    #expect(requests[0].httpBody == requests[1].httpBody)
    #expect(requests[0].value(forHTTPHeaderField: "Idempotency-Key") == requests[1].value(forHTTPHeaderField: "Idempotency-Key"))
    #expect(requests[0].value(forHTTPHeaderField: "X-Sure-Payload-SHA256") == requests[1].value(forHTTPHeaderField: "X-Sure-Payload-SHA256"))
    let applied = try await store.load()
    #expect(applied.pendingCapture == nil)
    #expect(applied.nextSequence == 2)
    #expect(applied.checkpoint == state.pendingCapture?.nextCheckpoint)
  }

  @Test("Logout during rotation prevents the returned credential from being installed")
  func revocationDuringRotation() async throws {
    let environment = environment()
    defer { try? FileManager.default.removeItem(at: environment.stateURL.deletingLastPathComponent()) }
    let configuration = try configuration()
    let state = pendingState(configuration)
    let store = FinanceKitPublisherStateFileStore(fileURL: environment.stateURL)
    try await store.save(state)
    let credentials = PublisherCredentials()
    let barrier = PublisherRotationBarrier()
    let gate = BackendAccessGate()
    gate.update(expiration: .distantFuture)
    let controller = FinanceKitPublisherController(gate: gate, makeEnvironment: { environment },
      makeCredentialStore: { _ in credentials }, remoteRenew: { _ in
        await barrier.wait()
        return (configuration, "must-not-be-installed")
      })
    let renewal = Task { try await controller.renewCredential() }
    await barrier.waitUntilStarted()
    try controller.blockBackgroundDelivery()
    await barrier.resume()
    await #expect(throws: FinanceKitBatchUploadError.publisherRevoked) { try await renewal.value }
    #expect(try credentials.credential(for: configuration.publisherID) == "test-only")
    #expect(await controller.configuredConnectionID() == nil)
  }

  @Test("Repair explicitly resets the old stream, while renewal rejects stream changes")
  func repairChangesStream() async throws {
    let environment = environment()
    defer { try? FileManager.default.removeItem(at: environment.stateURL.deletingLastPathComponent()) }
    let previous = try configuration()
    var replacement = previous
    replacement.generation += 1
    replacement.streamID = UUID(uuidString: "40000000-0000-4000-8000-000000000002")!
    let configuration = replacement
    let state = pendingState(previous)
    let store = FinanceKitPublisherStateFileStore(fileURL: environment.stateURL)
    try await store.save(state)
    let credentials = PublisherCredentials()
    let gate = BackendAccessGate()
    gate.update(expiration: .distantFuture)
    let controller = FinanceKitPublisherController(gate: gate, makeEnvironment: { environment },
      makeCredentialStore: { _ in credentials }, remoteRenew: { _ in (configuration, "invalid-renewal") },
      remoteRepair: { _ in (configuration, "repaired-secret") })
    await #expect(throws: FinanceKitSyncError.invalidState) { try await controller.renewCredential() }
    #expect(try await store.load() == state)
    try await controller.repair()
    var expected = FinanceKitPublisherState.empty
    expected.configuration = configuration
    #expect(try await store.load() == expected)
    #expect(try credentials.credential(for: configuration.publisherID) == "repaired-secret")
  }

  private func pendingState(_ configuration: FinanceKitPublisherConfiguration) -> FinanceKitPublisherState {
    var state = FinanceKitPublisherState.empty
    state.configuration = configuration
    state.checkpoint = Data("prior-checkpoint".utf8)
    state.predecessorDigest = "prior-digest"
    state.lastAcceptedAt = Date(timeIntervalSince1970: 1_789_700_000)
    state.pendingCapture = .init(id: UUID(uuidString: "60000000-0000-4000-8000-000000000001")!,
      nextCheckpoint: Data("next-checkpoint".utf8), batches: [
        .init(id: UUID(uuidString: "50000000-0000-4000-8000-000000000001")!, sequence: 1,
          predecessorDigest: "prior-digest",
          payloadDigest: "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08", body: Data("{}".utf8))
      ], nextBatchIndex: 0)
    return state
  }

  private func environment() -> FinanceKitPublisherEnvironment {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    return .init(stateURL: folder.appendingPathComponent("state.json"), lockURL: folder.appendingPathComponent("lock"),
      revocationURL: folder.appendingPathComponent("revoked"), keychainAccessGroup: "test-only")
  }

  private func configuration() throws -> FinanceKitPublisherConfiguration {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let value = try decoder.singleValueContainer().decode(String.self)
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      return try #require(formatter.date(from: value))
    }
    return try decoder.decode(FinanceKitActivation.self, from: APIFixture.data(named: "financekit-activation")).configuration()
  }
}

private final class PublisherCredentials: FinanceKitPublisherCredentialStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var value: String? = "test-only"
  var isEmpty: Bool { lock.withLock { value == nil } }
  func credential(for publisherID: UUID) throws -> String? { lock.withLock { value } }
  func saveCredential(_ credential: String, for publisherID: UUID) throws { lock.withLock { value = credential } }
  func removeCredential(for publisherID: UUID) throws { try removeAllCredentials() }
  func removeAllCredentials() throws { lock.withLock { value = nil } }
}

private struct UnexpectedPublisherCollector: FinanceKitChangeCollecting {
  func collect(configuration: FinanceKitPublisherConfiguration, checkpoint: Data?,
               changedTypes: Set<FinanceKitBackgroundDataType>) async throws -> FinanceKitCollectedChanges {
    Issue.record("Renewal must replay the durable outbox without recollecting Wallet data")
    throw FinanceKitSyncError.invalidState
  }
}

private actor PublisherRotationBarrier {
  private var continuation: CheckedContinuation<Void, Never>?
  private var started: CheckedContinuation<Void, Never>?
  private(set) var calls = 0
  func wait() async {
    calls += 1
    await withCheckedContinuation {
      continuation = $0
      started?.resume()
      started = nil
    }
  }
  func waitUntilStarted() async {
    if continuation != nil { return }
    await withCheckedContinuation { started = $0 }
  }
  func resume() { continuation?.resume(); continuation = nil }
}
