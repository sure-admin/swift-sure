import CryptoKit
import Foundation

struct FinanceKitBatchPlanner: Sendable {
  var makeID: @Sendable () -> UUID

  init(makeID: @escaping @Sendable () -> UUID = { UUID() }) {
    self.makeID = makeID
  }

  func plan(
    configuration: FinanceKitPublisherConfiguration,
    state: FinanceKitPublisherState,
    changes: FinanceKitCollectedChanges
  ) throws -> FinanceKitPendingCapture? {
    guard !changes.events.isEmpty else { return nil }
    guard state.pendingCapture == nil, state.nextSequence > 0 else {
      throw FinanceKitSyncError.invalidState
    }

    let chunks = try chunks(
      for: changes,
      configuration: configuration
    )
    let finalSequence = state.nextSequence.addingReportingOverflow(UInt64(chunks.count - 1))
    guard !finalSequence.overflow else {
      throw FinanceKitSyncError.sequenceExhausted
    }

    let captureID = makeID()
    var sequence = state.nextSequence
    var predecessor = state.predecessorDigest
    var batches: [FinanceKitPendingBatch] = []
    batches.reserveCapacity(chunks.count)

    for (index, events) in chunks.enumerated() {
      let batchID = makeID()
      let payload = FinanceKitBatchPayload(
        protocolVersion: configuration.protocolVersion,
        connectionID: configuration.connectionID,
        publisherID: configuration.publisherID,
        generation: configuration.generation,
        streamID: configuration.streamID,
        batchID: batchID,
        sequence: sequence,
        predecessorDigest: predecessor,
        captureID: captureID,
        chunkIndex: index,
        chunkCount: chunks.count,
        captureMode: changes.mode,
        snapshotComplete: changes.mode == .snapshot && index == chunks.count - 1,
        capturedAt: changes.capturedAt,
        selectedSourceAccountIDs: configuration.consent.selectedSourceAccountIDs,
        events: events
      )
      let body = try Self.encoder().encode(payload)
      guard body.count <= configuration.maxBytesPerBatch else {
        throw FinanceKitSyncError.eventTooLarge
      }
      let digest = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
      batches.append(FinanceKitPendingBatch(
        id: batchID,
        sequence: sequence,
        predecessorDigest: predecessor,
        payloadDigest: digest,
        body: body
      ))
      predecessor = digest
      let advanced = sequence.addingReportingOverflow(1)
      guard !advanced.overflow else { throw FinanceKitSyncError.sequenceExhausted }
      sequence = advanced.partialValue
    }

    return FinanceKitPendingCapture(
      id: captureID,
      nextCheckpoint: changes.nextCheckpoint,
      batches: batches,
      nextBatchIndex: 0
    )
  }

  private func chunks(
    for changes: FinanceKitCollectedChanges,
    configuration: FinanceKitPublisherConfiguration
  ) throws -> [[FinanceKitSourceEvent]] {
    var chunks: [[FinanceKitSourceEvent]] = []
    var current: [FinanceKitSourceEvent] = []
    let baseSize = try sizingPayload(
      events: [],
      changes: changes,
      configuration: configuration
    ).count
    var currentSize = baseSize

    for event in changes.events {
      let eventSize = try Self.encoder().encode(event).count
      let separatorSize = current.isEmpty ? 0 : 1
      if current.count == configuration.maxRecordsPerBatch
        || currentSize + separatorSize + eventSize > configuration.maxBytesPerBatch {
        guard !current.isEmpty else { throw FinanceKitSyncError.eventTooLarge }
        chunks.append(current)
        current = []
        currentSize = baseSize
      }
      guard currentSize + eventSize <= configuration.maxBytesPerBatch else {
        throw FinanceKitSyncError.eventTooLarge
      }
      if !current.isEmpty { currentSize += 1 }
      current.append(event)
      currentSize += eventSize
    }
    if !current.isEmpty { chunks.append(current) }
    return chunks
  }

  private func sizingPayload(
    events: [FinanceKitSourceEvent],
    changes: FinanceKitCollectedChanges,
    configuration: FinanceKitPublisherConfiguration
  ) throws -> Data {
    let placeholder = UUID(uuidString: "ffffffff-ffff-4fff-bfff-ffffffffffff")!
    let payload = FinanceKitBatchPayload(
      protocolVersion: configuration.protocolVersion,
      connectionID: configuration.connectionID,
      publisherID: configuration.publisherID,
      generation: configuration.generation,
      streamID: configuration.streamID,
      batchID: placeholder,
      sequence: UInt64.max,
      predecessorDigest: String(repeating: "f", count: 64),
      captureID: placeholder,
      chunkIndex: Swift.max(changes.events.count - 1, 0),
      chunkCount: Swift.max(changes.events.count, 1),
      captureMode: changes.mode,
      snapshotComplete: false,
      capturedAt: changes.capturedAt,
      selectedSourceAccountIDs: configuration.consent.selectedSourceAccountIDs,
      events: events
    )
    return try Self.encoder().encode(payload)
  }

  private static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .custom { date, encoder in
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      var container = encoder.singleValueContainer()
      try container.encode(formatter.string(from: date))
    }
    return encoder
  }
}
