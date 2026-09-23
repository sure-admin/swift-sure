import Foundation

struct FinanceKitPublisherState: Codable, Equatable, Sendable {
  static let currentSchemaVersion = 1

  var schemaVersion: Int
  var configuration: FinanceKitPublisherConfiguration?
  var checkpoint: Data?
  var nextSequence: UInt64
  var predecessorDigest: String?
  var pendingCapture: FinanceKitPendingCapture?
  var requiresRepair: Bool
  var lastAcceptedAt: Date?
  var batchRejection: FinanceKitBatchRejection? = nil

  static var empty: FinanceKitPublisherState {
    FinanceKitPublisherState(
      schemaVersion: currentSchemaVersion,
      configuration: nil,
      checkpoint: nil,
      nextSequence: 1,
      predecessorDigest: nil,
      pendingCapture: nil,
      requiresRepair: false,
      lastAcceptedAt: nil
    )
  }
}
