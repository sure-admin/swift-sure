import Foundation

protocol FinanceKitPublisherLifecycleHandling: Sendable {
  func install(configuration: FinanceKitPublisherConfiguration, credential: String) async throws
  func renewCredential() async throws
  func repair() async throws
  func blockBackgroundDelivery() throws
  /// The connection this device publishes to, read back from durable publisher
  /// state so a relaunched app can reach the control plane without re-enrolling.
  func configuredConnectionID() async -> UUID?
  func requiresRepair() async -> Bool
  func batchRejection() async -> FinanceKitBatchRejection?
  func batchValidationIssue() async -> FinanceKitEventValidationIssue?
  func resumeIfConfigured() async
  func suspend() async
  func hasPendingConsentWithdrawal() async -> Bool
  func stopKeepingHistory() async throws
  func disconnect() async throws
}

extension FinanceKitPublisherLifecycleHandling {
  func hasPendingConsentWithdrawal() async -> Bool { false }
  func stopKeepingHistory() async throws { try await disconnect() }
  func requiresRepair() async -> Bool { false }
  func batchRejection() async -> FinanceKitBatchRejection? { nil }
  func batchValidationIssue() async -> FinanceKitEventValidationIssue? { nil }
}
