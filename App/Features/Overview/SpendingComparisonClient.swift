protocol SpendingComparisonClient: Sendable {
  func fetchComparison(for month: SpendingMonth) async throws -> SpendingComparison
}

enum SpendingComparisonServiceError: Error, Equatable {
  case unavailable
}
