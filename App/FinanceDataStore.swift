import Foundation
import Observation

@MainActor
@Observable
final class FinanceDataStore {
  static let shared = FinanceDataStore()

  var accounts: [FinanceAccount] = []
  var transactions: [FinanceTransaction] = []
  var budgets: [BudgetCategory] = []
  var state: FinanceDataState = .idle
  var lastUpdated: Date?

  var netWorth: Double {
    accounts.reduce(0) { $0 + $1.balance }
  }

  var monthIncome: Double {
    currentMonthTransactions
      .filter { $0.kind == .income }
      .reduce(0) { $0 + abs($1.amount) }
  }

  var monthSpending: Double {
    currentMonthTransactions
      .filter { $0.kind == .expense }
      .reduce(0) { $0 + abs($1.amount) }
  }

  var currentMonthTransactions: [FinanceTransaction] {
    transactions.filter { Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .month) }
  }

  private init() { }

  func refresh() async {
    let connection = SureConnection.shared
    guard connection.isConfigured else {
      state = .needsConnection
      return
    }
    state = .loading
    do {
      let client = SureAPIClient(connection: connection)
      async let loadedAccounts = client.fetchAccounts()
      async let loadedTransactions = client.fetchTransactions()
      accounts = try await loadedAccounts
      transactions = try await loadedTransactions
      budgets = (try? await client.fetchBudgetCategories()) ?? []
      lastUpdated = .now
      state = .loaded
    } catch {
      state = .failed(error.localizedDescription)
    }
  }
}

enum FinanceDataState: Equatable {
  case idle
  case loading
  case loaded
  case needsConnection
  case failed(String)
}
