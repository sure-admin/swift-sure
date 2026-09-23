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

  @Test("Validation code stays visible through refresh and foreground without another upload")
  func validationFailureIsActionable() async {
    let recorder = SyncRecorder(result: { throw FinanceKitBatchUploadError(kind: .rejected, code: "invalid_timestamp") })
    let store = makeStore(responses: Self.refreshResponses, recorder: recorder)
    await store.refresh()
    await store.sync()
    await store.refresh()
    await store.syncOnForeground()
    #expect(store.state == .repairRequired)
    #expect(store.rejectionMessage?.contains("HTTP 422: invalid_timestamp") == true)
    #expect(recorder.recordedCalls.count == 1)
  }

  @Test("Unknown response text is never included in persisted or displayed diagnostics")
  func unknownValidationCode() async {
    let secret = "unexpected server text containing private data"
    let recorder = SyncRecorder(result: { throw FinanceKitBatchUploadError(kind: .rejected, code: secret) })
    let store = makeStore(responses: Self.refreshResponses, recorder: recorder)
    await store.refresh()
    await store.sync()
    #expect(store.batchRejection == .unknown)
    #expect(store.rejectionMessage?.contains(secret) == false)
    #expect(store.rejectionMessage?.contains("HTTP 422") == true)
  }

  @Test("Relaunch restores the rejection; explicit repair clears it")
  func restoresValidationRejection() async {
    let publisher = FinanceKitPublisherStub(connectionID: Self.connection, rejection: .duplicateRecord)
    let transport = HTTPDataTransportStub(Self.refreshResponses)
    let store = store(transport: transport, publisher: publisher)
    await store.refresh()
    #expect(store.state == .repairRequired)
    #expect(store.rejectionMessage?.contains("duplicate_record") == true)
    #expect(await transport.requests().isEmpty)
    await store.repair()
    #expect(store.state == .active)
    #expect(store.rejectionMessage == nil)
    #expect(await publisher.repairs == 1)
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

  @Test("Local repair outcome survives a health refresh")
  func repairOutcomeIsVisible() async {
    let store = makeStore(responses: Self.refreshResponses, recorder: SyncRecorder(result: { .repairRequired }))
    await store.refresh()
    await store.sync()
    await store.refresh()
    #expect(store.state == .repairRequired)
  }

  @Test("Missing configuration clears previously displayed health")
  func notConfiguredClearsHealth() async {
    let store = makeStore(responses: Self.refreshResponses, recorder: SyncRecorder(result: { .notConfigured }))
    await store.refresh()
    await store.sync()
    #expect(store.state == .idle)
    #expect(store.health == nil)
    #expect(store.conflicts.isEmpty)
  }

  @Test("Logout clears the connection for refresh, repair and renewal")
  func logoutClearsConnection() async throws {
    let publisher = FinanceKitPublisherStub(connectionID: Self.connection)
    let transport = HTTPDataTransportStub(Self.refreshResponses)
    let store = store(transport: transport, publisher: publisher)
    await store.refresh()
    try await publisher.disconnect()
    await store.refresh()
    await store.repair()
    await store.renew()
    #expect(store.state == .idle)
    #expect(store.health == nil)
    #expect(await transport.requests().count == 2)
  }

  @Test("Existing durable configuration prevents another enrollment before refresh")
  func configuredEnrollmentDoesNotCreateConnection() async {
    let transport = HTTPDataTransportStub(Self.refreshResponses)
    let store = store(transport: transport, publisher: FinanceKitPublisherStub(connectionID: Self.connection))
    await store.enroll(accounts: [Self.account])
    #expect(store.state == .active)
    #expect(await transport.requests().allSatisfy { $0.httpMethod == "GET" })
  }

  @Test("All accounts are validated before any remote enrollment")
  func invalidAccountsDoNotEnroll() async {
    let transport = HTTPDataTransportStub([])
    let store = store(transport: transport, publisher: FinanceKitPublisherStub(connectionID: nil))
    var missingBalance = Self.account
    missingBalance.id = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
    missingBalance.balance = nil
    await store.enroll(accounts: [Self.account, missingBalance])
    #expect(await transport.requests().isEmpty)
    #expect(store.state == .failed("Wallet sync couldn’t be enabled. Try again."))
  }

  @Test("Mapping, activation and installation failures remove the new remote connection", arguments: [0, 1, 2])
  func enrollmentRollback(stage: Int) async throws {
    var responses: [HTTPDataTransportStub.Result] = [
      try .http(json: #"{"available":true}"#), try .http(fixture: "financekit-connection-health", status: 201)
    ]
    if stage > 0 { responses.append(try .http(json: Self.mappingJSON)) }
    if stage > 1 { responses.append(try .http(fixture: "financekit-activation")) }
    else { responses.append(.failure(URLError(.notConnectedToInternet))) }
    responses.append(try .http(status: 204))
    let transport = HTTPDataTransportStub(responses)
    let publisher = FinanceKitPublisherStub(connectionID: nil, failInstall: stage == 2)
    let store = store(transport: transport, publisher: publisher)
    await store.enroll(accounts: [Self.account])
    let requests = await transport.requests()
    #expect(requests.last?.httpMethod == "DELETE")
    #expect(requests.last?.url?.path == "/api/v1/financekit/connections/20000000-0000-4000-8000-000000000001")
    #expect(store.state == .failed("Wallet sync couldn’t be enabled. Try again."))
  }

  @Test("Successful enrollment installs one publisher and refreshes its health")
  func successfulEnrollment() async throws {
    let transport = HTTPDataTransportStub([
      try .http(json: #"{"available":true}"#), try .http(fixture: "financekit-connection-health", status: 201),
      try .http(json: Self.mappingJSON), try .http(fixture: "financekit-activation")
    ] + Self.refreshResponses)
    let publisher = FinanceKitPublisherStub(connectionID: nil)
    let store = store(transport: transport, publisher: publisher)
    await store.enroll(accounts: [Self.account])
    #expect(store.state == .active)
    #expect(await publisher.configuredConnectionID() == Self.connection)
    #expect(await transport.requests().map(\.httpMethod) == ["GET", "POST", "PUT", "POST", "GET", "GET"])
  }

  @Test("Failed rollback is retried before another enrollment")
  func failedRollbackPreventsDuplicate() async throws {
    let transport = HTTPDataTransportStub([
      try .http(json: #"{"available":true}"#), try .http(fixture: "financekit-connection-health", status: 201),
      .failure(URLError(.notConnectedToInternet)), .failure(URLError(.notConnectedToInternet)),
      .failure(URLError(.notConnectedToInternet))
    ])
    let store = store(transport: transport, publisher: FinanceKitPublisherStub(connectionID: nil))
    await store.enroll(accounts: [Self.account])
    await store.enroll(accounts: [Self.account])
    #expect(await transport.requests().map(\.httpMethod) == ["GET", "POST", "PUT", "DELETE", "DELETE"])
  }

  @Test("Overlapping enrollment and refresh cannot start another connection")
  func duplicateEnrollmentIsRejected() async throws {
    let gate = EnrollmentGate()
    let transport = HTTPDataTransportStub([try .http(json: #"{"available":false}"#)])
    let store = FinanceKitSyncStore(
      client: FinanceKitControlPlaneClient(transport: SureAPITransport(baseURL: URL(string: "https://sure.example")!,
        dataTransport: transport, authorizer: UnauthenticatedRequestAuthorizer())),
      publisher: FinanceKitPublisherStub(connectionID: nil), entitlementExpiration: { await gate.wait() })
    let first = Task { await store.enroll(accounts: [Self.account]) }
    await gate.waitUntilStarted()
    await store.refresh()
    await store.enroll(accounts: [Self.account])
    #expect(store.state == .enrolling)
    await gate.resume()
    await first.value
    #expect(await transport.requests().count == 1)
  }

  @Test("Publisher authorization recovers once and never loops", arguments: [false, true])
  func rejectedPublisherRecovery(alwaysReject: Bool) async throws {
    let attempts = PublisherSyncAttempts(alwaysReject: alwaysReject)
    let publisher = FinanceKitPublisherStub(connectionID: Self.connection)
    let transport = HTTPDataTransportStub(Self.refreshResponses + Self.refreshResponses)
    let store = FinanceKitSyncStore(client: FinanceKitControlPlaneClient(transport: SureAPITransport(
      baseURL: URL(string: "https://sure.example")!, dataTransport: transport,
      authorizer: UnauthenticatedRequestAuthorizer())), publisher: publisher,
      runSync: { _ in try await attempts.run() })
    await store.refresh()
    await store.sync()
    #expect(await attempts.count == 2)
    #expect(await publisher.renewals == 1)
    #expect(await transport.requests().allSatisfy { $0.httpMethod == "GET" })
    if alwaysReject {
      #expect(store.state == .failed("Wallet sync couldn’t finish. Try again."))
    } else {
      #expect(store.state == .active)
    }
  }

  @Test("Other upload failures never rotate the publisher credential", arguments: [
    FinanceKitBatchUploadError.authentication, .authorization, .publisherRevoked, .server(503)
  ])
  func otherFailuresDoNotRenew(error: FinanceKitBatchUploadError) async {
    let publisher = FinanceKitPublisherStub(connectionID: Self.connection)
    let store = FinanceKitSyncStore(client: FinanceKitControlPlaneClient(transport: SureAPITransport(
      baseURL: URL(string: "https://sure.example")!, dataTransport: HTTPDataTransportStub(Self.refreshResponses),
      authorizer: UnauthenticatedRequestAuthorizer())), publisher: publisher, runSync: { _ in throw error })
    await store.refresh()
    await store.sync()
    #expect(await publisher.renewals == 0)
  }

  @Test("Repeated renew, repair, refresh, and sync actions cannot overlap a renewal")
  func renewalRejectsOverlappingActions() async {
    let barrier = EnrollmentGate()
    let publisher = FinanceKitPublisherStub(connectionID: Self.connection, beforeRenew: { _ = await barrier.wait() })
    let transport = HTTPDataTransportStub(Self.refreshResponses + Self.refreshResponses)
    let store = store(transport: transport, publisher: publisher)
    await store.refresh()
    let renewal = Task { await store.renew() }
    await barrier.waitUntilStarted()
    #expect(store.isBusy)
    await store.renew()
    await store.repair()
    await store.refresh()
    await store.syncOnForeground()
    await store.sync()
    #expect(await publisher.renewals == 1)
    #expect(await publisher.repairs == 0)
    #expect(await transport.requests().count == 2)
    await barrier.resume()
    await renewal.value
    #expect(!store.isBusy)
    #expect(store.state == .active)
    #expect(await transport.requests().count == 4)
  }

  @Test("Renewal cannot be started while a foreground batch is uploading")
  func uploadingBlocksRenewal() async {
    let barrier = EnrollmentGate()
    let publisher = FinanceKitPublisherStub(connectionID: Self.connection)
    let store = FinanceKitSyncStore(client: FinanceKitControlPlaneClient(transport: SureAPITransport(
      baseURL: URL(string: "https://sure.example")!,
      dataTransport: HTTPDataTransportStub(Self.refreshResponses + Self.refreshResponses),
      authorizer: UnauthenticatedRequestAuthorizer())), publisher: publisher, runSync: { _ in
        _ = await barrier.wait()
        return .uploaded(1)
      })
    await store.refresh()
    let upload = Task { await store.sync() }
    await barrier.waitUntilStarted()
    await store.renew()
    await store.repair()
    #expect(await publisher.renewals == 0)
    #expect(await publisher.repairs == 0)
    await barrier.resume()
    await upload.value
    #expect(store.state == .active)
  }

  private static let account = LocalFinancialAccount(
    id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, name: "Wallet", institutionName: "Wallet",
    kind: .liability, balance: Money(minorUnits: 100, currency: CurrencyCode("USD")!))
  private static let mappingJSON = #"{"source_id":"00000000-0000-4000-8000-000000000001","lineage_id":"10000000-0000-4000-8000-000000000001","mapping_version":2}"#

  private func store(transport: HTTPDataTransportStub, publisher: FinanceKitPublisherStub) -> FinanceKitSyncStore {
    FinanceKitSyncStore(client: FinanceKitControlPlaneClient(transport: SureAPITransport(
      baseURL: URL(string: "https://sure.example")!, dataTransport: transport, authorizer: UnauthenticatedRequestAuthorizer())),
      publisher: publisher, entitlementExpiration: { Date.distantFuture }, runSync: { _ in .noChanges })
  }

  private static var refreshResponses: [HTTPDataTransportStub.Result] {
    [
      try! .http(fixture: "financekit-connection-health"),
      try! .http(json: #"{"conflicts":[]}"#)
    ]
  }

  private nonisolated static let connection = UUID(uuidString: "20000000-0000-4000-8000-000000000001")!

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
  private var connection: UUID?
  private let failInstall: Bool
  private var rejection: FinanceKitBatchRejection?

  private let beforeRenew: @Sendable () async -> Void
  init(connectionID: UUID?, failInstall: Bool = false, rejection: FinanceKitBatchRejection? = nil, beforeRenew: @escaping @Sendable () async -> Void = {}) {
    self.rejection = rejection
    connection = connectionID; self.failInstall = failInstall; self.beforeRenew = beforeRenew
  }

  func install(configuration: FinanceKitPublisherConfiguration, credential: String) async throws {
    if failInstall { throw FinanceKitSyncError.invalidState }
    connection = configuration.connectionID
  }
  nonisolated func blockBackgroundDelivery() { }
  func configuredConnectionID() async -> UUID? { connection }
  private(set) var renewals = 0
  private(set) var repairs = 0
  func renewCredential() async throws { renewals += 1; await beforeRenew() }
  func repair() async throws { repairs += 1; rejection = nil }
  func requiresRepair() async -> Bool { rejection != nil }
  func batchRejection() async -> FinanceKitBatchRejection? { rejection }
  func resumeIfConfigured() async { }
  func suspend() async { }
  func disconnect() async throws { connection = nil }
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

private actor EnrollmentGate {
  private var continuation: CheckedContinuation<Date?, Never>?
  private var started: CheckedContinuation<Void, Never>?
  func wait() async -> Date? {
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
  func resume() { continuation?.resume(returning: .distantFuture); continuation = nil }
}

private actor PublisherSyncAttempts {
  private(set) var count = 0
  private var alwaysReject: Bool
  init(alwaysReject: Bool) { self.alwaysReject = alwaysReject }
  func run() throws -> FinanceKitSyncOutcome {
    count += 1
    if count == 1 || alwaysReject { throw FinanceKitBatchUploadError.publisherUnauthorized }
    return .uploaded(1)
  }
}
