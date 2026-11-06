import SwiftUI

/// This separate executable uses production views with memory-only fixtures.
/// It has no production composition root, entitlements, SDK startup, or services.
@main
struct UITestApp: App {
  private let scenario: String
  private let connection: FixtureConnection
  private let client: FixtureClient
  private let finance: FinanceDataStore
  private let wallet: AppleCardConnectionStore
  private let comparison: SpendingComparisonStore
  private let factory: TransactionHistoryStoreFactory
  private let analytics: AnalyticsStore
  private let subscriptionAccess: SubscriptionAccessStore
  private let sureConnection: SureConnection
  private let telemetryBuildDetails: TelemetryBuildDetails

  init() {
    let scenario = ProcessInfo.processInfo.environment["SURE_SCENARIO"] ?? "onboarding"
    self.scenario = scenario
    let connection = FixtureConnection(preview: scenario == "onboarding")
    let client = FixtureClient(failFirst: scenario == "failure", syncedWallet: scenario == "wallet-synced")
    let wallet = AppleCardConnectionStore(connector: FixtureWallet())
    self.connection = connection; self.client = client; self.wallet = wallet
    finance = FinanceDataStore(connection: connection, client: client, calendar: .current,
      now: { FixtureClient.date }, syncInsights: { _ in })
    comparison = SpendingComparisonStore(client: client, connection: connection, calendar: .current,
      now: { FixtureClient.date }, walletClient: client, walletAccess: wallet)
    factory = TransactionHistoryStoreFactory(client: client, calendar: .current, now: { FixtureClient.date })
    analytics = AnalyticsStore(preferences: FixtureAnalyticsPreferences(), client: FixtureAnalyticsClient())
    subscriptionAccess = SubscriptionAccessStore(
      service: FixtureSubscriptionService(isEntitled: scenario == "sign-in-no-server"),
      gate: BackendAccessGate(now: { Date(timeIntervalSince1970: 0) }),
      waitUntil: { _ in throw CancellationError() }
    )
    sureConnection = SureConnection(
      initialState: SureConnectionInitialState(
        serverURL: ((scenario.hasPrefix("sign-in-") && scenario != "sign-in-no-server") || scenario == "connection-routing") ? SureDemoServer.baseURL.absoluteString : "",
        credentials: StoredCredentialSnapshot(session: nil),
        isExplicitlySignedOut: true, requestContext: nil, initializationError: nil
      ),
      authentication: FixtureAuthentication()
    )
    telemetryBuildDetails = TelemetryBuildDetails(
      postHogProjectToken: "phc_ui_fixture",
      sentryDSN: URL(string: "https://publickey@o1.ingest.example/42")
    )
  }

  var body: some Scene {
    WindowGroup {
      if scenario.hasPrefix("connection-routing") {
        FixtureConnectionRouting(subscriptionAccess: subscriptionAccess, connection: sureConnection,
          hasSyncAccess: scenario == "connection-routing")
      } else if scenario.hasPrefix("sign-in-") {
        Color.clear.sheet(isPresented: .constant(true)) {
          SignInView(subscriptionAccess: subscriptionAccess, connection: sureConnection,
            showConnectionSettings: {})
            .preferredColorScheme(scenario == "sign-in-dark" ? .dark : .light)
            .task { await subscriptionAccess.refresh() }
        }
      } else if scenario == "analytics-debug" {
        NavigationStack {
          AnalyticsSettingsView(analytics: analytics, buildDetails: telemetryBuildDetails)
        }
      } else if scenario == "subscription-sheet" {
        ConnectionSettingsView(subscriptionAccess: subscriptionAccess, connection: sureConnection,
          analytics: analytics, telemetryBuildDetails: telemetryBuildDetails,
          diagnostics: FixtureDiagnostics())
          .task { await subscriptionAccess.refresh() }
      } else if scenario == "wallet-consent" {
        FixtureFinanceKitSyncScreen(persistConsent: true)
      } else if scenario == "wallet-rejection" {
        FixtureFinanceKitSyncScreen(rejection: .invalidPayload)
      } else if scenario == "wallet-sync" {
        FixtureFinanceKitSyncScreen()
      } else {
        TabView {
          Tab("Accounts", systemImage: "building.columns") {
            AccountsView(data: finance,
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
}

private struct FixtureConnectionRouting: View {
  var subscriptionAccess: SubscriptionAccessStore
  var connection: SureConnection
  var hasSyncAccess: Bool
  @State private var presentation: ConnectionPresentation?

  var body: some View {
    FixtureConnectionPrompt(hasSyncAccess: hasSyncAccess)
      .modifier(ConnectionPresentationModifier(presentation: $presentation,
        subscriptionAccess: subscriptionAccess, connection: connection))
      .task { await subscriptionAccess.refresh() }
  }
}

private struct FixtureConnectionPrompt: View {
  @Environment(\.showConnectionSettings) private var showSettings
  var hasSyncAccess: Bool

  var body: some View {
    NavigationStack {
      SureConnectionPrompt(hasSyncAccess: hasSyncAccess)
        .toolbar {
          ToolbarItem(placement: .primaryAction) {
            Button("Settings", systemImage: "gearshape") { showSettings() }
              .labelStyle(.iconOnly)
          }
        }
    }
  }
}

@MainActor
private final class FixtureAnalyticsPreferences: AnalyticsPreferences {
  var analyticsEnabled = true
}

@MainActor
private final class FixtureAnalyticsClient: AnalyticsClient {
  func start() {}
  func stop() {}
  func capture(_ event: UsageEvent) {}
  func resetIdentity() {}
}

@MainActor
private struct FixtureSubscriptionService: SubscriptionServicing {
  var isEntitled = false
  func plans() async throws -> [SubscriptionPlan] {
    [SubscriptionPlan(id: "monthly", price: "$0.99", isAnnual: false,
      title: "Monthly", billingPeriod: "1 month")]
  }
  func entitlement() async -> SubscriptionEntitlement? {
    isEntitled ? SubscriptionEntitlement(expiration: Date(timeIntervalSince1970: 86_400), renewalCancelled: false) : nil
  }
  func purchase(_ id: String) async throws -> SubscriptionPurchaseOutcome { .cancelled }
  func restore() async throws {}
  func observe(_ changed: @escaping @MainActor () async -> Void) async {}
}

@MainActor
private final class FixtureDiagnostics: DiagnosticsControlling {
  var isEnabled = true
  var isAvailable: Bool { true }
  func setEnabled(_ enabled: Bool) { isEnabled = enabled }
  func log(_ record: DiagnosticRecord) {}
}

@MainActor
@Observable
private final class FixtureAuthentication: ConnectionAuthenticating {
  private(set) var status: ConnectionStatus = .notConnected
  var pendingOnboarding: MobileSSOOnboardingContext? { nil }
  var isConfigured: Bool { false }
  var isSignedOut: Bool { true }
  var generation: Int { 0 }
  var canLogOut: Bool { false }
  var allowsWalletPreview: Bool { false }
  var connectionID: String? { nil }
  var serverURL: URL? { nil }
  var isOAuthConnected: Bool { false }
  func matchesStoredAPIKey(_ key: String) -> Bool { false }
  func signIn(_ method: AuthenticationMethod, serverURL: String) async {
    if case .provider(.google) = method {
      status = .failed("Google sign-in started in the test fixture.")
    }
  }
  func cancel() {}
  func cancelOnboarding() {}
  func logOut() async {}
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
  private var syncedWallet: Bool
  init(failFirst: Bool, syncedWallet: Bool = false) { self.failFirst = failFirst; self.syncedWallet = syncedWallet }
  func fetchAccounts() async throws -> [FinanceAccount] {
    if syncedWallet {
      return [.init(id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!, name: "Synchronized Apple Card",
        institution: "Institution unavailable", kind: .credit,
        balance: Money(minorUnits: 12500, currency: CurrencyCode("USD")!), tintName: "orange", isLiability: true,
        walletSourceAccountID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!),
        .init(id: UUID(uuidString: "00000000-0000-4000-8000-000000000003")!, name: "Apple Card (Monthly)",
          institution: "Aggregator", kind: .credit, balance: Money(minorUnits: 9900, currency: CurrencyCode("USD")!), tintName: "orange")]
    }
    return [.init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "Sure Checking",
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
