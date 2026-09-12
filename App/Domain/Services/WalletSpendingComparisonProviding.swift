protocol WalletSpendingComparisonProviding: Sendable {
  func fetchComparison(for month: SpendingMonth, access: WalletSpendingAccess) async throws -> SpendingComparison
}
