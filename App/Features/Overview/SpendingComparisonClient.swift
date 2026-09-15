protocol SpendingComparisonClient: Sendable {
  func comparisonMetadata(for month: SpendingMonth) async -> ReadMetadata?
  func fetchComparison(for month: SpendingMonth) async throws -> SpendingComparison
}

enum SpendingComparisonServiceError: Error, Equatable {
  case unavailable
}

extension SpendingComparisonClient {
  func comparisonMetadata(for month: SpendingMonth) async -> ReadMetadata? { nil }
}
