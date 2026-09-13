import Foundation
import Testing
@testable import Sure

let testReadDate = ISO8601DateFormatter().date(from: "2024-02-15T12:00:00Z")!
var testReadCalendar: Calendar {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(secondsFromGMT: 0)!
  return calendar
}
let testReadAccount = FinanceAccount(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
  name: "Checking", institution: "Test", kind: .cash,
  balance: Money(minorUnits: 10000, currency: CurrencyCode("USD")!), tintName: "blue")
let testReadTransaction = FinanceTransaction(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
  merchant: "Market", category: "Food", symbol: "cart", date: try! LocalDate(year: 2024, month: 2, day: 15),
  amount: Money(minorUnits: 2500, currency: CurrencyCode("USD")!), kind: .expense, accountID: testReadAccount.id)

@MainActor
final class ReadConnectionFake: ConnectionStateProviding {
  var isConfigured = true
  var sessionGeneration = 0
  var allowsWalletPreview = false
  var id = "first-identity"
}

@MainActor
final class FinanceReadFake: FinanceDataClient, TransactionHistoryClient, FinancialSummaryProviding {
  var accountsFailure: Error?
  var accountsOperation: (() async -> [FinanceAccount])?
  var budgetOperation: (() async -> [BudgetCategory])?
  var transactions = [testReadTransaction]
  var summary: FinancialSummary?
  var summaryMonths: [SpendingMonth] = []
  var windows: [TransactionDateWindow] = []
  var accountCalls = 0
  var historyFailure: Error?
  func fetchBalanceSheet() async throws -> BalanceSheetRecord {
    let money = DecimalMoney(amount: 100, currency: CurrencyCode("USD")!)
    return BalanceSheetRecord(currency: money.currency, netWorth: money, assets: money, liabilities: .init(amount: 0, currency: money.currency))
  }
  func fetchAccounts() async throws -> [FinanceAccount] {
    accountCalls += 1
    if let accountsFailure { throw accountsFailure }
    return await accountsOperation?() ?? [testReadAccount]
  }
  func fetchTransactions(in dateWindow: TransactionDateWindow) async throws -> [FinanceTransaction] {
    try await fetchTransactions(.init(dateWindow: dateWindow))
  }
  func fetchTransactions(_ request: TransactionHistoryRequest) async throws -> [FinanceTransaction] {
    windows.append(request.dateWindow)
    if let historyFailure { throw historyFailure }
    return transactions
  }
  func fetchBudgetCategories() async throws -> [BudgetCategory] { await budgetOperation?() ?? [] }
  func fetchInsights() async throws -> [BackendInsight] { [] }
  func fetchSummary(for month: SpendingMonth) async throws -> FinancialSummary {
    summaryMonths.append(month)
    guard let summary, summary.month == month else { throw SureAPIError.notFound }
    return summary
  }
}

actor ReadBarrier<Value: Sendable> {
  private var pending: CheckedContinuation<Value, Never>?
  private var startWaiters: [CheckedContinuation<Void, Never>] = []
  func wait() async -> Value {
    await withCheckedContinuation { continuation in
      pending = continuation
      startWaiters.forEach { $0.resume() }; startWaiters.removeAll()
    }
  }
  func started() async {
    if pending != nil { return }
    await withCheckedContinuation { startWaiters.append($0) }
  }
  func finish(_ value: Value) { pending?.resume(returning: value); pending = nil }
}

func summaryFixture() throws -> FinancialSummary {
  try JSONDecoder().decode(FinancialSummaryDTO.self, from: APIFixture.data(named: "financial-summary-success")).record()
}
