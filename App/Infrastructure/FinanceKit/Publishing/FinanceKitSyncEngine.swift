import Foundation

actor FinanceKitSyncEngine {
  private var stateStore: any FinanceKitPublisherStateStoring
  private var collector: any FinanceKitChangeCollecting
  private var uploader: any FinanceKitBatchUploading
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
    self.uploader = uploader
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
      let receipt = try await uploader.upload(batch, configuration: configuration)
      guard receipt.connectionID == configuration.connectionID,
            receipt.publisherID == configuration.publisherID,
            receipt.generation == configuration.generation,
            receipt.streamID == configuration.streamID,
            receipt.batchID == batch.id,
            receipt.sequence == batch.sequence,
            receipt.payloadDigest == batch.payloadDigest else {
        throw FinanceKitSyncError.invalidReceipt
      }
      guard receipt.status != .failed else {
        state.requiresRepair = true
        try await stateStore.save(state)
        throw FinanceKitSyncError.streamFailed
      }

      let nextSequence = batch.sequence.addingReportingOverflow(1)
      guard !nextSequence.overflow else { throw FinanceKitSyncError.sequenceExhausted }
      state.nextSequence = nextSequence.partialValue
      state.predecessorDigest = batch.payloadDigest
      state.lastAcceptedAt = receipt.acceptedAt
      capture.nextBatchIndex += 1
      uploadedCount += 1

      if capture.nextBatchIndex == capture.batches.count {
        state.checkpoint = capture.nextCheckpoint
        state.pendingCapture = nil
      } else {
        state.pendingCapture = capture
      }
      try await stateStore.save(state)
    }

    guard state.pendingCapture == nil else { throw FinanceKitSyncError.invalidState }
    return .uploaded(uploadedCount)
  }
}
