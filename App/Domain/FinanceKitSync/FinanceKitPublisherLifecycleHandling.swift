import Foundation

protocol FinanceKitPublisherLifecycleHandling: Sendable {
  func install(configuration: FinanceKitPublisherConfiguration, credential: String) async throws
  func blockBackgroundDelivery() throws
  /// The connection this device publishes to, read back from durable publisher
  /// state so a relaunched app can reach the control plane without re-enrolling.
  func configuredConnectionID() async -> UUID?
  func requiresRepair() async -> Bool
  func resumeIfConfigured() async
  func suspend() async
  func disconnect() async throws
}

extension FinanceKitPublisherLifecycleHandling {
  func requiresRepair() async -> Bool { false }
}
