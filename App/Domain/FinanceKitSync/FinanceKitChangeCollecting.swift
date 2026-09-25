import Foundation

protocol FinanceKitChangeCollecting: Sendable {
  func collect(
    configuration: FinanceKitPublisherConfiguration,
    checkpoint: Data?,
    changedTypes: Set<FinanceKitBackgroundDataType>
  ) async throws -> FinanceKitCollectedChanges
}
