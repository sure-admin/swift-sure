import Foundation
import Testing
@testable import Sure

@MainActor
@Suite("FinanceKit foreground sync")
struct FinanceKitSyncStoreTests {
  @Test("Sync now collects everything since the checkpoint")
  func syncCollectsEverything() async throws {
    let recorder = SyncRecorder()
    let store = makeStore(responses: Self.refreshResponses + Self.refreshResponses, recorder: recorder)

    await store.refresh()
    await store.sync()

    #expect(recorder.recordedCalls == [[]])
    #expect(store.state == .active)
  }

  @Test("A capture Sure has accepted but not imported reads as importing, not as a failure")
  func pendingImportIsNotAFailure() async throws {
    let recorder = SyncRecorder(result: { throw FinanceKitSyncError.importPending })
    let store = makeStore(responses: Self.refreshResponses, recorder: recorder)

    await store.refresh()
    await store.sync()

    #expect(store.state == .importing)
  }

  @Test("Losing the process lock is not shown to the user as a failure")
  func lockContentionIsNotAFailure() async throws {
    let recorder = SyncRecorder(result: { throw FinanceKitProcessLockError.busy })
    let store = makeStore(responses: Self.refreshResponses + Self.refreshResponses, recorder: recorder)

    await store.refresh()
    await store.sync()

    #expect(store.state == .active)
  }

  @Test("An unexpected failure is reported once the user can act on it")
  func unexpectedFailureIsReported() async throws {
    let recorder = SyncRecorder(result: { throw FinanceKitSyncError.invalidReceipt })
    let store = makeStore(responses: Self.refreshResponses, recorder: recorder)

    await store.refresh()
    await store.sync()

    #expect(store.state == .failed("Wallet sync couldn’t finish. Try again."))
  }

  @Test("Re-entering the foreground twice in a minute syncs once")
  func foregroundSyncIsDebounced() async throws {
    let recorder = SyncRecorder()
    let clock = TestClock(Date(timeIntervalSince1970: 1_789_725_600))
    let store = makeStore(
      responses: Self.refreshResponses + Self.refreshResponses + Self.refreshResponses + Self.refreshResponses,
      recorder: recorder,
      now: { clock.now }
    )

    await store.syncOnForeground()
    await store.syncOnForeground()
    #expect(recorder.recordedCalls.count == 1)

    clock.advance(FinanceKitSyncStore.foregroundSyncInterval + 1)
    await store.syncOnForeground()
    #expect(recorder.recordedCalls.count == 2)
  }

  @Test("A device that is not a configured publisher never reaches the runner")
  func unconfiguredDeviceDoesNotSync() async throws {
    let recorder = SyncRecorder()
    let store = makeStore(responses: [], recorder: recorder, connectionID: nil)

    await store.syncOnForeground()

    #expect(recorder.recordedCalls.isEmpty)
    #expect(store.state == .idle)
  }

  @Test("A relaunched app recovers its connection from durable publisher state")
  func refreshRecoversConnectionWithoutEnrolling() async throws {
    let store = makeStore(responses: Self.refreshResponses, recorder: SyncRecorder())

    await store.refresh()

    #expect(store.state == .active)
    #expect(store.health?.lastAcceptedAt == Date(timeIntervalSince1970: 1_789_725_601))
    #expect(store.health?.lastImportedAt == Date(timeIntervalSince1970: 1_789_725_604))
  }

  private static var refreshResponses: [HTTPDataTransportStub.Result] {
    [
      try! .http(fixture: "financekit-connection-health"),
      try! .http(json: #"{"conflicts":[]}"#)
    ]
  }

  private static let connection = UUID(uuidString: "20000000-0000-4000-8000-000000000001")!

  private func makeStore(
    responses: [HTTPDataTransportStub.Result],
    recorder: SyncRecorder,
    connectionID: UUID? = FinanceKitSyncStoreTests.connection,
    now: @escaping @Sendable () -> Date = { .now }
  ) -> FinanceKitSyncStore {
    let transport = SureAPITransport(
      baseURL: URL(string: "https://sure.example")!,
      dataTransport: HTTPDataTransportStub(responses),
      authorizer: UnauthenticatedRequestAuthorizer()
    )
    return FinanceKitSyncStore(
      client: FinanceKitControlPlaneClient(transport: transport),
      publisher: FinanceKitPublisherStub(connectionID: connectionID),
      runSync: { try recorder.run($0) },
      now: now
    )
  }
}

private actor FinanceKitPublisherStub: FinanceKitPublisherLifecycleHandling {
  private let connection: UUID?

  init(connectionID: UUID?) { connection = connectionID }

  func install(configuration: FinanceKitPublisherConfiguration, credential: String) async throws { }
  nonisolated func blockBackgroundDelivery() { }
  func configuredConnectionID() async -> UUID? { connection }
  func resumeIfConfigured() async { }
  func suspend() async { }
  func disconnect() async throws { }
}

private final class SyncRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var calls: [Set<FinanceKitBackgroundDataType>] = []
  private let result: @Sendable () throws -> FinanceKitSyncOutcome

  init(result: @escaping @Sendable () throws -> FinanceKitSyncOutcome = { .uploaded(1) }) {
    self.result = result
  }

  var recordedCalls: [Set<FinanceKitBackgroundDataType>] { lock.withLock { calls } }

  func run(_ changedTypes: Set<FinanceKitBackgroundDataType>) throws -> FinanceKitSyncOutcome {
    lock.withLock { calls.append(changedTypes) }
    return try result()
  }
}

private final class TestClock: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Date

  init(_ value: Date) { self.value = value }

  var now: Date { lock.withLock { value } }

  func advance(_ interval: TimeInterval) {
    lock.withLock { value = value.addingTimeInterval(interval) }
  }
}
