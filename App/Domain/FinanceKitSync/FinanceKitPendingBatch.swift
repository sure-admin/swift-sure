import Foundation

struct FinanceKitPendingBatch: Codable, Equatable, Sendable {
  var id: UUID
  var sequence: UInt64
  var predecessorDigest: String?
  var payloadDigest: String
  var body: Data
}
