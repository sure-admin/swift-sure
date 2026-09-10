extension SureToolInventory {
  /// Reviewed local implementations only; server availability never enables local code.
  var isAvailableOnMobile: Bool { self == .getAccounts }

  /// Explicit allowlist: unknown and newly mirrored tools fail closed, including writes.
  var permitsServerDelegation: Bool {
    switch self {
    case .getAccounts, .getTransactions, .getRecurringTransactions, .getHoldings,
         .getBalanceSheet, .getIncomeStatement, .getBudget, .getTags, .getCategories,
         .getMerchants, .searchFamilyFiles, .listAccountStatements, .getAccountStatement,
         .getStatementCoverage, .getValuations, .getInsights:
      true
    default:
      false
    }
  }
}
