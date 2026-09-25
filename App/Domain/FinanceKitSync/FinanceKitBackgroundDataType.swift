enum FinanceKitBackgroundDataType: String, Codable, CaseIterable, Hashable, Sendable {
  case accounts
  case accountBalances = "account_balances"
  case transactions
}
