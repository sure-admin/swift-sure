import SwiftUI

/// This separate executable uses production views with memory-only fixtures.
/// It has no production composition root, entitlements, SDK startup, or services.
@main
struct UITestApp: App {
  private let connection: FixtureConnection
  private let client: FixtureClient
  private let finance: FinanceDataStore
  private let wallet: AppleCardConnectionStore
  private let comparison: SpendingComparisonStore
  private let factory: TransactionHistoryStoreFactory

  init() {
    let scenario = ProcessInfo.processInfo.environment["SURE_SCENARIO"] ?? "onboarding"
    let connection = FixtureConnection(preview: scenario == "onboarding")
    let client = FixtureClient(failFirst: scenario == "failure")
    let wallet = AppleCardConnectionStore(connector: FixtureWallet())
    self.connection = connection; self.client = client; self.wallet = wallet
    finance = FinanceDataStore(connection: connection, client: client, calendar: .current,
      now: { FixtureClient.date }, syncInsights: { _ in })
    comparison = SpendingComparisonStore(client: client, connection: connection, calendar: .current,
      now: { FixtureClient.date }, walletClient: client, walletAccess: wallet)
    factory = TransactionHistoryStoreFactory(client: client, calendar: .current, now: { FixtureClient.date })
  }

  var body: some Scene {
    WindowGroup {
      TabView {
        Tab("Accounts", systemImage: "building.columns") {
          AccountsView(data: finance, allowsWalletPreview: connection.allowsWalletPreview,
            hasSyncAccess: connection.isConfigured, appleCardConnection: wallet,
            transactionHistoryStoreFactory: factory, localTransactionHistoryStoreFactory: factory)
        }
        Tab("Spending", systemImage: "chart.xyaxis.line") {
          ScrollView { SpendingComparisonCard(store: comparison).padding() }
            .task { if connection.allowsWalletPreview { await wallet.refresh() } }
        }
      }
    }
  }
}

@MainActor
private final class FixtureConnection: ConnectionStateProviding {
  var isConfigured: Bool { !allowsWalletPreview }
  var sessionGeneration = 0
  let allowsWalletPreview: Bool
  init(preview: Bool) { allowsWalletPreview = preview }
}

private struct FixtureWallet: AppleCardConnecting {
  var isAvailable: Bool { true }
  func authorizationStatus() async throws -> AppleCardAuthorization { .authorized }
  func requestAuthorization() async throws -> AppleCardAuthorization { .authorized }
  func fetchAccounts() async throws -> [LocalFinancialAccount] {
    [.init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Apple Card Preview",
      institutionName: "Wallet", kind: .liability, balance: Money(minorUnits: 12500, currency: CurrencyCode("USD")!))]
  }
}

@MainActor
private final class FixtureClient: FinanceDataClient, TransactionHistoryClient, SpendingComparisonClient, WalletSpendingComparisonProviding {
  static let date = ISO8601DateFormatter().date(from: "2024-02-15T12:00:00Z")!
  private var failFirst: Bool
  init(failFirst: Bool) { self.failFirst = failFirst }
  func fetchAccounts() async throws -> [FinanceAccount] {
    [.init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "Sure Checking",
      institution: "Sure", kind: .cash, balance: Money(minorUnits: 50000, currency: CurrencyCode("USD")!), tintName: "blue")]
  }
  func fetchBalanceSheet() async throws -> BalanceSheetRecord { throw DataFailure.unavailable }
  func fetchTransactions(in dateWindow: TransactionDateWindow) async throws -> [FinanceTransaction] { [] }
  func fetchTransactions(_ request: TransactionHistoryRequest) async throws -> [FinanceTransaction] { [] }
  func fetchBudgetCategories() async throws -> [BudgetCategory] { [] }
  func fetchInsights() async throws -> [BackendInsight] { [] }
  func fetchComparison(for month: SpendingMonth, access: WalletSpendingAccess) async throws -> SpendingComparison {
    try await fetchComparison(for: month)
  }
  func fetchComparison(for month: SpendingMonth) async throws -> SpendingComparison {
    if failFirst { failFirst = false; throw DataFailure.offline }
    let asOf = try LocalDate(year: 2024, month: 2, day: 15)
    let previous = month.shifted(by: -1)
    return try SpendingComparison(month: month, asOf: asOf, currency: CurrencyCode("USD")!,
      current: (1...(month == SpendingMonth(containing: asOf) ? 15 : month.dayCount)).map { .init(date: try month.date(day: $0), amount: Decimal($0 * 10)) },
      previous: (1...previous.dayCount).map { .init(date: try previous.date(day: $0), amount: Decimal($0 * 12)) })
  }
}
