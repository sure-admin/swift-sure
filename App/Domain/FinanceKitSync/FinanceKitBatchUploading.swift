protocol FinanceKitBatchUploading: Sendable {
  func upload(
    _ batch: FinanceKitPendingBatch,
    configuration: FinanceKitPublisherConfiguration
  ) async throws -> FinanceKitBatchReceipt
}
