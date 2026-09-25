import Foundation

actor FinanceKitSyncEngine {
  private var stateStore: any FinanceKitPublisherStateStoring
  private var collector: any FinanceKitChangeCollecting
  private var makeUploader: @Sendable (FinanceKitPublisherConfiguration) throws -> any FinanceKitBatchUploading
  private var processLock: FinanceKitProcessLock
  private var planner: FinanceKitBatchPlanner

  init(
    stateStore: any FinanceKitPublisherStateStoring,
    collector: any FinanceKitChangeCollecting,
    uploader: any FinanceKitBatchUploading,
    processLock: FinanceKitProcessLock,
    planner: FinanceKitBatchPlanner = FinanceKitBatchPlanner()
  ) {
    self.stateStore = stateStore
    self.collector = collector
    self.makeUploader = { _ in uploader }
    self.processLock = processLock
    self.planner = planner
  }

  init(
    stateStore: any FinanceKitPublisherStateStoring,
    collector: any FinanceKitChangeCollecting,
    makeUploader: @escaping @Sendable (FinanceKitPublisherConfiguration) throws -> any FinanceKitBatchUploading,
    processLock: FinanceKitProcessLock,
    planner: FinanceKitBatchPlanner = FinanceKitBatchPlanner()
  ) {
    self.stateStore = stateStore
    self.collector = collector
    self.makeUploader = makeUploader
    self.processLock = processLock
    self.planner = planner
  }

  func synchronize(
    changedTypes: Set<FinanceKitBackgroundDataType> = []
  ) async throws -> FinanceKitSyncOutcome {
    let lock = try processLock.acquire()
    defer { _ = lock }

    var state = try await stateStore.load()
    guard let configuration = state.configuration else { return .notConfigured }
    guard !state.requiresRepair else { return .repairRequired }
    // Resolve the credential against this configuration while holding the lock,
    // so neither a renewal nor a repair can leave an uploader with a stale secret.
    let uploader = try makeUploader(configuration)

    if state.pendingCapture == nil {
      let changes: FinanceKitCollectedChanges
      do {
        changes = try await collector.collect(
          configuration: configuration,
          checkpoint: state.checkpoint,
          changedTypes: changedTypes
        )
      } catch FinanceKitSyncError.historyTokenInvalid {
        state.requiresRepair = true
        try await stateStore.save(state)
        return .repairRequired
      }

      guard let pending = try planner.plan(
        configuration: configuration,
        state: state,
        changes: changes
      ) else {
        state.checkpoint = changes.nextCheckpoint
        try await stateStore.save(state)
        return .noChanges
      }
      state.pendingCapture = pending
      try await stateStore.save(state)
    }

    var uploadedCount = 0
    while var capture = state.pendingCapture, let batch = capture.currentBatch {
      let receipt: FinanceKitBatchReceipt
      do {
        receipt = try await uploader.upload(batch, configuration: configuration)
      } catch let error as FinanceKitBatchUploadError where error.kind == .rejected {
        // Replaying identical bytes cannot fix validation. Preserve the outbox
        // and checkpoint until explicit server repair establishes a new stream.
        state.batchRejection = FinanceKitBatchRejection(serverCode: error.code)
        state.requiresRepair = true
        try await stateStore.save(state)
        throw error
      }
      try validate(receipt, for: batch, configuration: configuration)
      guard receipt.status != .failed else {
        state.requiresRepair = true
        try await stateStore.save(state)
        throw FinanceKitSyncError.streamFailed
      }
      capture.nextBatchIndex += 1
      state.pendingCapture = capture
      uploadedCount += 1
      try await stateStore.save(state)
    }

    guard let capture = state.pendingCapture, capture.nextBatchIndex == capture.batches.count,
          let finalBatch = capture.batches.last else { throw FinanceKitSyncError.invalidState }
    let finalReceipt = try await uploader.status(finalBatch, configuration: configuration)
    try validate(finalReceipt, for: finalBatch, configuration: configuration)
    guard finalReceipt.status == .applied else {
      state.requiresRepair = finalReceipt.status == .failed
      try await stateStore.save(state)
      throw finalReceipt.status == .failed ? FinanceKitSyncError.streamFailed : FinanceKitSyncError.importPending
    }
    let nextSequence = finalBatch.sequence.addingReportingOverflow(1)
    guard !nextSequence.overflow else { throw FinanceKitSyncError.sequenceExhausted }
    state.nextSequence = nextSequence.partialValue
    state.predecessorDigest = finalBatch.payloadDigest
    state.lastAcceptedAt = finalReceipt.acceptedAt
    state.checkpoint = capture.nextCheckpoint
    state.pendingCapture = nil
    try await stateStore.save(state)

    guard state.pendingCapture == nil else { throw FinanceKitSyncError.invalidState }
    return .uploaded(uploadedCount)
  }

  private func validate(
    _ receipt: FinanceKitBatchReceipt,
    for batch: FinanceKitPendingBatch,
    configuration: FinanceKitPublisherConfiguration
  ) throws {
    guard receipt.connectionID == configuration.connectionID,
          receipt.publisherID == configuration.publisherID,
          receipt.generation == configuration.generation,
          receipt.streamID == configuration.streamID,
          receipt.batchID == batch.id,
          receipt.sequence == batch.sequence,
          receipt.payloadDigest == batch.payloadDigest else {
      throw FinanceKitSyncError.invalidReceipt
    }
  }
}
