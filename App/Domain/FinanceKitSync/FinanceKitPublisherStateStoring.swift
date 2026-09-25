protocol FinanceKitPublisherStateStoring: Sendable {
  func load() async throws -> FinanceKitPublisherState
  func save(_ state: FinanceKitPublisherState) async throws
  func clear() async throws
}
