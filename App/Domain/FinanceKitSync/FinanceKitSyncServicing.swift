import Foundation

protocol FinanceKitChangeCollecting: Sendable {
  func collect(
    configuration: FinanceKitPublisherConfiguration,
    checkpoint: Data?,
    changedTypes: Set<FinanceKitBackgroundDataType>
  ) async throws -> FinanceKitCollectedChanges
}

protocol FinanceKitBatchUploading: Sendable {
  func upload(
    _ batch: FinanceKitPendingBatch,
    configuration: FinanceKitPublisherConfiguration
  ) async throws -> FinanceKitBatchReceipt
}

protocol FinanceKitPublisherStateStoring: Sendable {
  func load() async throws -> FinanceKitPublisherState
  func save(_ state: FinanceKitPublisherState) async throws
  func clear() async throws
}

protocol FinanceKitPublisherCredentialStoring: Sendable {
  func credential(for publisherID: UUID) throws -> String?
  func saveCredential(_ credential: String, for publisherID: UUID) throws
  func removeCredential(for publisherID: UUID) throws
  func removeAllCredentials() throws
}

protocol FinanceKitPublisherLifecycleHandling: Sendable {
  func resumeIfConfigured() async
  func suspend() async
  func disconnect() async throws
}
