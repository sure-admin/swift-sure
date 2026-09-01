import Foundation

struct FinanceDataSnapshot {
  var serverURL: URL
  var connectionIdentity: String
  var balanceSheet: BalanceSheetRecord?
  var accounts: [FinanceAccount]
  var transactions: [FinanceTransaction]
  var budgets: [BudgetCategory]
  var insights: [BackendInsight]
  var lastUpdated: Date?
}
