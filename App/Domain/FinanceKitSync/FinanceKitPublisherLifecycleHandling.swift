protocol FinanceKitPublisherLifecycleHandling: Sendable {
  func blockBackgroundDelivery()
  func resumeIfConfigured() async
  func suspend() async
  func disconnect() async throws
}
