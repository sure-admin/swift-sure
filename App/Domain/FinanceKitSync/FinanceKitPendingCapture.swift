import Foundation

struct FinanceKitPendingCapture: Codable, Equatable, Sendable {
  var id: UUID
  var nextCheckpoint: Data
  var batches: [FinanceKitPendingBatch]
  var nextBatchIndex: Int

  var currentBatch: FinanceKitPendingBatch? {
    batches.indices.contains(nextBatchIndex) ? batches[nextBatchIndex] : nil
  }
}
