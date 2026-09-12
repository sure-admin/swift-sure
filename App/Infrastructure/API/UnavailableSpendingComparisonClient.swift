/// Replace at the composition root once Sure publishes the spending API.
/// Do not substitute transaction sums or scrape authenticated dashboard HTML.
struct UnavailableSpendingComparisonClient: SpendingComparisonClient {
  func fetchComparison(for month: SpendingMonth) async throws -> SpendingComparison {
    throw SpendingComparisonServiceError.unavailable
  }
}
