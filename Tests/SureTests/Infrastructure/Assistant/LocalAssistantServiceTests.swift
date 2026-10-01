import Foundation
import Testing
@testable import Sure

@MainActor
@Suite("Local assistant service")
struct LocalAssistantServiceTests {
  @Test("The emitted prompt uses authoritative net worth instead of account arithmetic")
  func authoritativeNetWorthContext() throws {
    let usd = try #require(CurrencyCode("USD"))
    let authoritativeNetWorth = DecimalMoney(
      amount: Decimal(string: "9876.54")!,
      currency: usd
    )
    let firstBalance = Money(minorUnits: 10_000, currency: usd)
    let secondBalance = Money(minorUnits: 20_000, currency: usd)
    let reconstructedNetWorth = try #require(firstBalance.adding(secondBalance))
    let store = makeStore()
    store.balanceSheet = BalanceSheetRecord(
      currency: usd,
      netWorth: authoritativeNetWorth,
      assets: DecimalMoney(amount: Decimal(string: "10876.54")!, currency: usd),
      liabilities: DecimalMoney(amount: Decimal(1_000), currency: usd)
    )
    store.accounts = [
      account(id: 1, name: "Checking", balance: firstBalance),
      account(id: 2, name: "Savings", balance: secondBalance)
    ]

    let prompt = LocalAssistantService(financeData: store).localPrompt(
      question: "What is my net worth?",
      conversation: []
    )

    #expect(prompt.contains("Net worth: \(FinanceFormatters.currency(authoritativeNetWorth))"))
    #expect(!prompt.contains("Net worth: \(FinanceFormatters.currency(reconstructedNetWorth))"))
    #expect(!prompt.contains("Checking"))
    #expect(!prompt.contains("Savings"))
    #expect(prompt.contains("Current question:\nWhat is my net worth?"))
  }

  @Test("The prompt identifies provenance and does not aggregate raw transactions")
  func incompleteContext() {
    let store = makeStore()
    store.transactions = [testReadTransaction]
    let prompt = LocalAssistantService(financeData: store).localPrompt(question: "Summarize this month.", conversation: [])
    #expect(prompt.contains("potentially incomplete or stale"))
    #expect(prompt.contains("No live server query"))
    #expect(prompt.contains("Period income: Unavailable"))
    #expect(prompt.contains("Period spending: Unavailable"))
  }

  #if canImport(FoundationModels)
  @available(iOS 26.0, macOS 26.0, *)
  @Test("Account tool preserves signed balances and currency precision")
  func accountToolBalances() async throws {
    let store = makeStore()
    store.accounts = try [("USD", Int64(-12345)), ("JPY", 0), ("KWD", 1234567),
                          ("BTC", 1), ("USD", 9007199254740993)].enumerated().map { index, value in
      account(id: index, name: "Synthetic \(index)", balance: Money(
        minorUnits: value.1, currency: try #require(CurrencyCode(value.0))
      ))
    }
    let output = try await LocalGetAccountsTool(financeData: store).call(arguments: .init())
    let result = try JSONDecoder().decode(AccountToolResult.self, from: Data(output.utf8))
    #expect(result.status == "available")
    #expect(result.accounts.map(\.balance) == ["-123.45", "0", "1234.567", "0.00000001", "90071992547409.93"])
    #expect(result.accounts.map(\.currency) == ["USD", "JPY", "KWD", "BTC", "USD"])
    #expect(result.accounts.map(\.name) == store.accounts.map(\.name))
    #expect(result.accounts.map(\.id) == store.accounts.map(\.id))
  }

  @available(iOS 26.0, macOS 26.0, *)
  @Test("Account tool distinguishes empty, unavailable, failed and cleared snapshots")
  func accountToolAvailability() async throws {
    let store = makeStore()
    let tool = LocalGetAccountsTool(financeData: store)
    func result() async throws -> AccountToolResult {
      let output = try await tool.call(arguments: .init())
      return try JSONDecoder().decode(AccountToolResult.self, from: Data(output.utf8))
    }
    #expect(try await result().status == "unavailable")
    store.state = .loaded
    #expect(try await result().status == "available")
    #expect(try await result().accounts.isEmpty)
    store.accounts = [account(id: 1, name: "Checking", balance: Money(
      minorUnits: 100, currency: try #require(CurrencyCode("USD"))
    ))]
    store.accountsError = "Synthetic failure"
    #expect(try await result().status == "unavailable")
    #expect(try await result().accounts.isEmpty)
    store.accountsError = nil
    #expect(try await result().accounts.count == 1)
    store.accounts = []
    store.state = .needsConnection
    #expect(try await result().status == "unavailable")
    #expect(try await result().accounts.isEmpty)
  }
  #endif

  private func makeStore(
    now: Date = Date(timeIntervalSince1970: 1_800_000_000)
  ) -> FinanceDataStore {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return FinanceDataStore(
      connection: LocalAssistantConnectionStub(),
      client: UnusedLocalAssistantFinanceDataClient(),
      calendar: calendar,
      now: { now },
      syncInsights: { _ in }
    )
  }

  private func account(id: Int, name: String, balance: Money) -> FinanceAccount {
    FinanceAccount(
      id: localAssistantID(id),
      name: name,
      institution: "Synthetic institution",
      kind: .cash,
      balance: balance,
      tintName: "blue"
    )
  }

  private func transaction(
    id: Int,
    date: LocalDate,
    amount: Money,
    kind: TransactionKind
  ) -> FinanceTransaction {
    FinanceTransaction(
      id: localAssistantID(id),
      merchant: "Synthetic merchant",
      category: "Synthetic category",
      symbol: "creditcard.fill",
      date: date,
      amount: amount,
      kind: kind,
      accountID: localAssistantID(1)
    )
  }
}

private final class LocalAssistantConnectionStub: ConnectionStateProviding {
  var isConfigured = true
  var sessionGeneration = 0
}

private struct UnusedLocalAssistantFinanceDataClient: FinanceDataClient {
  func fetchBalanceSheet() async throws -> BalanceSheetRecord {
    throw UnusedLocalAssistantClientError.unexpectedCall
  }

  func fetchAccounts() async throws -> [FinanceAccount] {
    throw UnusedLocalAssistantClientError.unexpectedCall
  }

  func fetchTransactions(
    in dateWindow: TransactionDateWindow
  ) async throws -> [FinanceTransaction] {
    throw UnusedLocalAssistantClientError.unexpectedCall
  }

  func fetchBudgetCategories() async throws -> [BudgetCategory] {
    throw UnusedLocalAssistantClientError.unexpectedCall
  }

  func fetchInsights() async throws -> [BackendInsight] {
    throw UnusedLocalAssistantClientError.unexpectedCall
  }
}

private enum UnusedLocalAssistantClientError: Error {
  case unexpectedCall
}

private struct AccountToolResult: Decodable {
  var status: String
  var accounts: [Account]

  struct Account: Decodable {
    var id: UUID
    var name: String
    var balance: String
    var currency: String
  }
}

private func localAssistantID(_ sequence: Int) -> UUID {
  UUID(uuid: (
    0, 0, 0, 0,
    0, 0,
    0, 0,
    0, 0,
    0, 0, 0, 0, 1, UInt8(truncatingIfNeeded: sequence)
  ))
}
