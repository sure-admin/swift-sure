import Foundation

struct FinanceKitBatchPayload: Codable, Equatable, Sendable {
  var protocolVersion: Int
  var connectionID: UUID
  var publisherID: UUID
  var generation: UInt64
  var streamID: UUID
  var batchID: UUID
  var sequence: UInt64
  var predecessorDigest: String?
  var captureID: UUID
  var chunkIndex: Int
  var chunkCount: Int
  var captureMode: FinanceKitCaptureMode
  var snapshotComplete: Bool
  var capturedAt: Date
  var selectedSourceAccountIDs: [UUID]
  var events: [FinanceKitSourceEvent]

  private enum CodingKeys: String, CodingKey {
    case protocolVersion = "protocol_version"
    case connectionID = "connection_id"
    case publisherID = "publisher_id"
    case generation
    case streamID = "stream_id"
    case batchID = "batch_id"
    case sequence
    case predecessorDigest = "predecessor_digest"
    case captureID = "capture_id"
    case chunkIndex = "chunk_index"
    case chunkCount = "chunk_count"
    case captureMode = "capture_mode"
    case snapshotComplete = "snapshot_complete"
    case capturedAt = "captured_at"
    case selectedSourceAccountIDs = "selected_source_account_ids"
    case events
  }
}
