import Foundation

struct FinanceKitBatchReceipt: Codable, Equatable, Sendable {
  enum Status: String, Codable, Sendable {
    case accepted
    case processing
    case applied
    case failed
  }

  var connectionID: UUID
  var publisherID: UUID
  var generation: UInt64
  var streamID: UUID
  var batchID: UUID
  var sequence: UInt64
  var payloadDigest: String
  var status: Status
  var acceptedAt: Date
  /// Set once the server has imported the batch; nil while it is only accepted.
  var appliedAt: Date?
  /// The server's reason when `status` is `failed`.
  var errorCode: String?

  private enum CodingKeys: String, CodingKey {
    case connectionID = "connection_id"
    case publisherID = "publisher_id"
    case generation
    case streamID = "stream_id"
    case batchID = "batch_id"
    case sequence
    case payloadDigest = "payload_digest"
    case status
    case acceptedAt = "accepted_at"
    case appliedAt = "applied_at"
    case errorCode = "error_code"
  }
}
