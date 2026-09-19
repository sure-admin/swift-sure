protocol FinanceKitPublisherLifecycleHandling: Sendable {
  func install(configuration: FinanceKitPublisherConfiguration, credential: String) async throws
  func blockBackgroundDelivery()
  func resumeIfConfigured() async
  func suspend() async
  func disconnect() async throws
}
