import Foundation

protocol FinanceKitPublisherLifecycleHandling: Sendable {
  func install(configuration: FinanceKitPublisherConfiguration, credential: String) async throws
  func blockBackgroundDelivery()
  /// The connection this device publishes to, read back from durable publisher
  /// state so a relaunched app can reach the control plane without re-enrolling.
  func configuredConnectionID() async -> UUID?
  func resumeIfConfigured() async
  func suspend() async
  func disconnect() async throws
}
