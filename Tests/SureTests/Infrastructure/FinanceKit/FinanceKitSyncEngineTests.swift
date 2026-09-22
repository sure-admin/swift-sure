import Foundation
import Testing
@testable import Sure

@Suite("FinanceKit background publisher")
struct FinanceKitSyncEngineTests {
  @Test("An empty initial snapshot uploads its completion marker")
  func emptySnapshot() async throws {
    let checkpoint = Data("empty-snapshot-checkpoint".utf8)
    let changes = FinanceKitCollectedChanges(
      mode: .snapshot,
      capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
      events: [],
      nextCheckpoint: checkpoint
    )
    let store = MemoryFinanceKitPublisherStateStore(state: configuredState())
    let collector = FinanceKitCollectorFake(behavior: .changes(changes))
    let uploader = FinanceKitUploaderFake()
    let harness = try makeEngine(store: store, collector: collector, uploader: uploader)

    #expect(try await harness.engine.synchronize() == .uploaded(1))

    let batches = await uploader.uploadedBatches()
    let batch = try #require(batches.first)
    let payload = try decodePayload(batch)
    #expect(batches.count == 1)
    #expect(payload.events.isEmpty)
    #expect(payload.captureMode == .snapshot)
    #expect(payload.snapshotComplete)
    let state = try await store.load()
    #expect(state.checkpoint == checkpoint)
    #expect(state.nextSequence == 2)
    #expect(state.pendingCapture == nil)
    try? FileManager.default.removeItem(at: harness.directory)
  }

  @Test("An empty delta advances its checkpoint without uploading")
  func emptyDelta() async throws {
    let checkpoint = Data("empty-delta-checkpoint".utf8)
    let changes = FinanceKitCollectedChanges(
      mode: .delta,
      capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
      events: [],
      nextCheckpoint: checkpoint
    )
    let store = MemoryFinanceKitPublisherStateStore(state: configuredState())
    let collector = FinanceKitCollectorFake(behavior: .changes(changes))
    let uploader = FinanceKitUploaderFake()
    let harness = try makeEngine(store: store, collector: collector, uploader: uploader)

    #expect(try await harness.engine.synchronize() == .noChanges)
    #expect(await uploader.uploadedBatches().isEmpty)
    let state = try await store.load()
    #expect(state.checkpoint == checkpoint)
    #expect(state.nextSequence == 1)
    try? FileManager.default.removeItem(at: harness.directory)
  }

  @Test("A catch-up larger than 500 records advances its token only after every ordered chunk is accepted")
  func chunkedCatchUp() async throws {
    let checkpoint = Data("checkpoint-2".utf8)
    let changes = FinanceKitCollectedChanges(
      mode: .snapshot,
      capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
      events: (0..<1_001).map(event),
      nextCheckpoint: checkpoint
    )
    let store = MemoryFinanceKitPublisherStateStore(state: configuredState())
    let collector = FinanceKitCollectorFake(behavior: .changes(changes))
    let uploader = FinanceKitUploaderFake()
    let harness = try makeEngine(store: store, collector: collector, uploader: uploader)

    #expect(try await harness.engine.synchronize() == .uploaded(3))

    let state = try await store.load()
    #expect(state.checkpoint == checkpoint)
    #expect(state.pendingCapture == nil)
    #expect(state.nextSequence == 4)
    let batches = await uploader.uploadedBatches()
    #expect(batches.map(\.sequence) == [1, 2, 3])
    #expect(batches[1].predecessorDigest == batches[0].payloadDigest)
    #expect(batches[2].predecessorDigest == batches[1].payloadDigest)
    let payloads = try batches.map(decodePayload)
    #expect(payloads.map { $0.events.count } == [500, 500, 1])
    #expect(payloads.map(\.snapshotComplete) == [false, false, true])
    #expect(await collector.callCount() == 1)
    try? FileManager.default.removeItem(at: harness.directory)
  }

  @Test("Encoded byte limits split records before transport")
  func byteLimitedCatchUp() async throws {
    let changes = FinanceKitCollectedChanges(
      mode: .delta,
      capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
      events: (0..<20).map(event),
      nextCheckpoint: Data("byte-checkpoint".utf8)
    )
    let store = MemoryFinanceKitPublisherStateStore(
      state: configuredState(maxBytesPerBatch: 2_000)
    )
    let collector = FinanceKitCollectorFake(behavior: .changes(changes))
    let uploader = FinanceKitUploaderFake()
    let harness = try makeEngine(store: store, collector: collector, uploader: uploader)

    let outcome = try await harness.engine.synchronize()
    let batches = await uploader.uploadedBatches()
    #expect(batches.count > 1)
    #expect(batches.allSatisfy { $0.body.count <= 2_000 })
    #expect(outcome == .uploaded(batches.count))
    #expect((try await store.load()).checkpoint == Data("byte-checkpoint".utf8))
    try? FileManager.default.removeItem(at: harness.directory)
  }

  @Test("A lost response retries the exact immutable batch without advancing the history token")
  func lostAcknowledgement() async throws {
    let checkpoint = Data("checkpoint-after-ack".utf8)
    let changes = FinanceKitCollectedChanges(
      mode: .delta,
      capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
      events: [event(1)],
      nextCheckpoint: checkpoint
    )
    let store = MemoryFinanceKitPublisherStateStore(state: configuredState())
    let collector = FinanceKitCollectorFake(behavior: .changes(changes))
    let uploader = FinanceKitUploaderFake(failuresRemaining: 1)
    let harness = try makeEngine(store: store, collector: collector, uploader: uploader)

    await #expect(throws: FinanceKitUploaderFake.Failure.self) {
      try await harness.engine.synchronize()
    }
    var state = try await store.load()
    #expect(state.checkpoint == nil)
    #expect(state.pendingCapture?.nextBatchIndex == 0)

    #expect(try await harness.engine.synchronize() == .uploaded(1))
    state = try await store.load()
    #expect(state.checkpoint == checkpoint)
    let batches = await uploader.uploadedBatches()
    #expect(batches.count == 2)
    #expect(batches[0] == batches[1])
    #expect(await collector.callCount() == 1)
    try? FileManager.default.removeItem(at: harness.directory)
  }

  @Test("An invalid Apple history token stops the stream for explicit repair")
  func invalidHistoryToken() async throws {
    let store = MemoryFinanceKitPublisherStateStore(state: configuredState())
    let collector = FinanceKitCollectorFake(behavior: .invalidToken)
    let uploader = FinanceKitUploaderFake()
    let harness = try makeEngine(store: store, collector: collector, uploader: uploader)

    #expect(try await harness.engine.synchronize() == .repairRequired)
    #expect((try await store.load()).requiresRepair)
    #expect(await uploader.uploadedBatches().isEmpty)
    try? FileManager.default.removeItem(at: harness.directory)
  }

  @Test("A receipt that does not bind the exact batch leaves the outbox and checkpoint untouched")
  func mismatchedReceipt() async throws {
    let changes = FinanceKitCollectedChanges(
      mode: .delta,
      capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
      events: [event(1)],
      nextCheckpoint: Data("later".utf8)
    )
    let store = MemoryFinanceKitPublisherStateStore(state: configuredState())
    let collector = FinanceKitCollectorFake(behavior: .changes(changes))
    let uploader = FinanceKitUploaderFake(returnsMismatchedReceipt: true)
    let harness = try makeEngine(store: store, collector: collector, uploader: uploader)

    await #expect(throws: FinanceKitSyncError.invalidReceipt) {
      try await harness.engine.synchronize()
    }
    let state = try await store.load()
    #expect(state.checkpoint == nil)
    #expect(state.pendingCapture?.nextBatchIndex == 0)
    #expect(state.nextSequence == 1)
    try? FileManager.default.removeItem(at: harness.directory)
  }

  @Test("A capture the server has accepted but not imported keeps its outbox and its checkpoint")
  func acceptedButNotImported() async throws {
    let changes = FinanceKitCollectedChanges(
      mode: .delta,
      capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
      events: [event(1)],
      nextCheckpoint: Data("import-pending-checkpoint".utf8)
    )
    let store = MemoryFinanceKitPublisherStateStore(state: configuredState())
    let collector = FinanceKitCollectorFake(behavior: .changes(changes))
    let uploader = FinanceKitUploaderFake(statusSequence: [.accepted])
    let harness = try makeEngine(store: store, collector: collector, uploader: uploader)

    await #expect(throws: FinanceKitSyncError.importPending) {
      try await harness.engine.synchronize()
    }

    let state = try await store.load()
    #expect(state.requiresRepair == false)
    #expect(state.checkpoint == nil)
    #expect(state.nextSequence == 1)
    #expect(state.pendingCapture?.nextBatchIndex == 1)
    try? FileManager.default.removeItem(at: harness.directory)
  }

  @Test("A later pass resumes a pending import without re-collecting or re-uploading")
  func pendingImportResumes() async throws {
    let checkpoint = Data("import-resumed-checkpoint".utf8)
    let changes = FinanceKitCollectedChanges(
      mode: .delta,
      capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
      events: [event(1)],
      nextCheckpoint: checkpoint
    )
    let store = MemoryFinanceKitPublisherStateStore(state: configuredState())
    let collector = FinanceKitCollectorFake(behavior: .changes(changes))
    let uploader = FinanceKitUploaderFake(statusSequence: [.processing, .applied])
    let harness = try makeEngine(store: store, collector: collector, uploader: uploader)

    await #expect(throws: FinanceKitSyncError.importPending) {
      try await harness.engine.synchronize()
    }
    #expect(try await harness.engine.synchronize() == .uploaded(0))

    let state = try await store.load()
    #expect(state.checkpoint == checkpoint)
    #expect(state.pendingCapture == nil)
    #expect(state.nextSequence == 2)
    #expect(await collector.callCount() == 1)
    #expect(await uploader.uploadedBatches().count == 1)
    #expect(await uploader.statusCallCount() == 2)
    try? FileManager.default.removeItem(at: harness.directory)
  }

  @Test("A failed final receipt fences the stream for repair rather than reporting a pending import")
  func failedFinalReceipt() async throws {
    let changes = FinanceKitCollectedChanges(
      mode: .delta,
      capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
      events: [event(1)],
      nextCheckpoint: Data("fenced-checkpoint".utf8)
    )
    let store = MemoryFinanceKitPublisherStateStore(state: configuredState())
    let collector = FinanceKitCollectorFake(behavior: .changes(changes))
    let uploader = FinanceKitUploaderFake(statusSequence: [.failed])
    let harness = try makeEngine(store: store, collector: collector, uploader: uploader)

    await #expect(throws: FinanceKitSyncError.streamFailed) {
      try await harness.engine.synchronize()
    }

    let state = try await store.load()
    #expect(state.requiresRepair)
    #expect(state.checkpoint == nil)
    try? FileManager.default.removeItem(at: harness.directory)
  }

  private func makeEngine(
    store: MemoryFinanceKitPublisherStateStore,
    collector: FinanceKitCollectorFake,
    uploader: FinanceKitUploaderFake
  ) throws -> (engine: FinanceKitSyncEngine, directory: URL) {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("financekit-sync-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return (
      FinanceKitSyncEngine(
        stateStore: store,
        collector: collector,
        uploader: uploader,
        processLock: FinanceKitProcessLock(url: directory.appendingPathComponent("sync.lock")),
        planner: FinanceKitBatchPlanner(makeID: LockedFinanceKitIDSource().make)
      ),
      directory
    )
  }

  private func configuredState(
    maxBytesPerBatch: Int = 1_000_000
  ) -> FinanceKitPublisherState {
    var state = FinanceKitPublisherState.empty
    state.configuration = try! configuration(maxBytesPerBatch: maxBytesPerBatch)
    return state
  }

  private func configuration(
    maxBytesPerBatch: Int = 1_000_000
  ) throws -> FinanceKitPublisherConfiguration {
    let source = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    return try FinanceKitPublisherConfiguration(
      serverURL: URL(string: "https://sure.example")!,
      uploadURL: URL(string: "https://sure.example/api/v1/financekit/connections/device/batches")!,
      connectionID: UUID(uuidString: "20000000-0000-4000-8000-000000000001")!,
      publisherID: UUID(uuidString: "30000000-0000-4000-8000-000000000001")!,
      generation: 1,
      streamID: UUID(uuidString: "40000000-0000-4000-8000-000000000001")!,
      consent: FinanceKitUploadConsent(
        grantedAt: Date(timeIntervalSince1970: 1_699_999_000),
        selectedSourceAccountIDs: [source],
        uploadAuthorized: true,
        familyVisibilityAcknowledged: true,
        remoteProcessingAcknowledged: true
      ),
      accountBindings: [FinanceKitAccountBinding(
        sourceAccountID: source,
        lineageID: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!,
        mappingVersion: 1
      )],
      maxRecordsPerBatch: 500,
      maxBytesPerBatch: maxBytesPerBatch
    )
  }

  private func event(_ value: Int) -> FinanceKitSourceEvent {
    .transactionTombstone(FinanceKitSourceTransactionTombstone(
      sourceID: UUID(value: value),
      sourceAccountID: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
      lineageID: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!,
      mappingVersion: 1
    ))
  }

  private func decodePayload(_ batch: FinanceKitPendingBatch) throws -> FinanceKitBatchPayload {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let value = try container.decode(String.self)
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      guard let date = formatter.date(from: value) else {
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date")
      }
      return date
    }
    return try decoder.decode(FinanceKitBatchPayload.self, from: batch.body)
  }
}

private actor MemoryFinanceKitPublisherStateStore: FinanceKitPublisherStateStoring {
  private var state: FinanceKitPublisherState

  init(state: FinanceKitPublisherState) { self.state = state }
  func load() async throws -> FinanceKitPublisherState { state }
  func save(_ state: FinanceKitPublisherState) async throws { self.state = state }
  func clear() async throws { state = .empty }
}

private actor FinanceKitCollectorFake: FinanceKitChangeCollecting {
  enum Behavior: Sendable {
    case changes(FinanceKitCollectedChanges)
    case invalidToken
  }

  private var behavior: Behavior
  private var calls = 0

  init(behavior: Behavior) { self.behavior = behavior }

  func collect(
    configuration: FinanceKitPublisherConfiguration,
    checkpoint: Data?,
    changedTypes: Set<FinanceKitBackgroundDataType>
  ) throws -> FinanceKitCollectedChanges {
    calls += 1
    switch behavior {
    case .changes(let changes): return changes
    case .invalidToken: throw FinanceKitSyncError.historyTokenInvalid
    }
  }

  func callCount() -> Int { calls }
}

private actor FinanceKitUploaderFake: FinanceKitBatchUploading {
  enum Failure: Error { case interrupted }

  private var batches: [FinanceKitPendingBatch] = []
  private var failuresRemaining: Int
  private var returnsMismatchedReceipt: Bool
  private var statusSequence: [FinanceKitBatchReceipt.Status]
  private var statusCalls = 0

  init(
    failuresRemaining: Int = 0,
    returnsMismatchedReceipt: Bool = false,
    statusSequence: [FinanceKitBatchReceipt.Status] = []
  ) {
    self.failuresRemaining = failuresRemaining
    self.returnsMismatchedReceipt = returnsMismatchedReceipt
    self.statusSequence = statusSequence
  }

  func upload(
    _ batch: FinanceKitPendingBatch,
    configuration: FinanceKitPublisherConfiguration
  ) throws -> FinanceKitBatchReceipt {
    batches.append(batch)
    if failuresRemaining > 0 {
      failuresRemaining -= 1
      throw Failure.interrupted
    }
    return FinanceKitBatchReceipt(
      connectionID: configuration.connectionID,
      publisherID: configuration.publisherID,
      generation: configuration.generation,
      streamID: configuration.streamID,
      batchID: returnsMismatchedReceipt ? UUID() : batch.id,
      sequence: batch.sequence,
      payloadDigest: batch.payloadDigest,
      status: .accepted,
      acceptedAt: Date(timeIntervalSince1970: 1_700_000_001)
    )
  }

  func status(
    _ batch: FinanceKitPendingBatch,
    configuration: FinanceKitPublisherConfiguration
  ) throws -> FinanceKitBatchReceipt {
    statusCalls += 1
    var status = FinanceKitBatchReceipt.Status.applied
    if !statusSequence.isEmpty { status = statusSequence.removeFirst() }
    return FinanceKitBatchReceipt(
      connectionID: configuration.connectionID,
      publisherID: configuration.publisherID,
      generation: configuration.generation,
      streamID: configuration.streamID,
      batchID: returnsMismatchedReceipt ? UUID() : batch.id,
      sequence: batch.sequence,
      payloadDigest: batch.payloadDigest,
      status: status,
      acceptedAt: Date(timeIntervalSince1970: 1_700_000_001),
      appliedAt: status == .applied ? Date(timeIntervalSince1970: 1_700_000_004) : nil,
      errorCode: status == .failed ? "stream_fenced" : nil
    )
  }

  func uploadedBatches() -> [FinanceKitPendingBatch] { batches }
  func statusCallCount() -> Int { statusCalls }
}

private final class LockedFinanceKitIDSource: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 1

  func make() -> UUID {
    lock.withLock {
      defer { value += 1 }
      return UUID(value: value)
    }
  }
}

private extension UUID {
  init(value: Int) {
    self = UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", value))!
  }
}
