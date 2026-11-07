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
    client.insightDismissalFailure = scenario.contains("failure")
    client.showInsights = scenario.hasPrefix("insight-dismissal")
    self.connection = connection; self.client = client; self.wallet = wallet
    finance = FinanceDataStore(connection: connection, client: client, calendar: .current,
      now: { FixtureClient.date }, syncInsights: { _ in })
    comparison = SpendingComparisonStore(client: client, connection: connection, calendar: .current,
      now: { FixtureClient.date }, walletClient: client, walletAccess: wallet)
    factory = TransactionHistoryStoreFactory(client: client, calendar: .current, now: { FixtureClient.date })
    analytics = AnalyticsStore(preferences: FixtureAnalyticsPreferences(), client: FixtureAnalyticsClient())
    subscriptionAccess = SubscriptionAccessStore(
      service: FixtureSubscriptionService(isEntitled: (scenario == "sign-in-no-server" || scenario.hasPrefix("settings-paid"))),
      gate: BackendAccessGate(now: { Date(timeIntervalSince1970: 0) }),
      waitUntil: { _ in throw CancellationError() }
    )
    sureConnection = SureConnection(
      initialState: SureConnectionInitialState(
        serverURL: ((scenario.hasPrefix("sign-in-") && scenario != "sign-in-no-server") || scenario == "connection-routing") ? SureDemoServer.baseURL.absoluteString : "",
        credentials: StoredCredentialSnapshot(session: nil),
        isExplicitlySignedOut: true, requestContext: nil, initializationError: nil
      ),
      authentication: FixtureAuthentication(canLogOut: scenario == "settings-locked", requiresSecondFactor: scenario.hasPrefix("sign-in-mfa"))
    )
    telemetryBuildDetails = TelemetryBuildDetails(
      postHogProjectToken: "phc_ui_fixture",
      sentryDSN: URL(string: "https://publickey@o1.ingest.example/42")
    )
    if scenario.hasPrefix("sign-in-progress") || scenario.hasPrefix("sign-in-mfa") { sureConnection.prepareDemoSignIn() }
  }

  var body: some Scene {
    WindowGroup {
      if scenario.hasPrefix("insight-dismissal") {
        ScrollView {
          InsightCard(insights: finance.insights, isLoading: finance.isLoadingInsights,
            errorMessage: finance.insightError, notificationManager: FixtureInsightNotifications(),
            statusColumnWidth: 56, acknowledgingIDs: finance.acknowledgingInsightIDs,
            acknowledgmentError: finance.insightAcknowledgmentError,
            acknowledge: { insight in Task { await finance.acknowledgeInsight(insight) } })
            .padding()
        }
        .preferredColorScheme(scenario.hasSuffix("dark") ? .dark : .light)
        .task { await finance.refresh() }
      } else if scenario.hasPrefix("connection-routing") {
        FixtureConnectionRouting(subscriptionAccess: subscriptionAccess, connection: sureConnection,
          hasSyncAccess: scenario == "connection-routing")
      } else if scenario.hasPrefix("sign-in-") {
        Color.clear.sheet(isPresented: .constant(true)) {
          SignInView(subscriptionAccess: subscriptionAccess, connection: sureConnection,
            showConnectionSettings: {})
            .preferredColorScheme(scenario.hasSuffix("dark") ? .dark : .light)
            .task { await subscriptionAccess.refresh() }
        }
      } else if scenario == "analytics-debug" {
        NavigationStack {
          AnalyticsSettingsView(analytics: analytics, buildDetails: telemetryBuildDetails)
        }
      } else if scenario == "subscription-sheet" {
        NavigationStack {
          SubscriptionAccessView(access: subscriptionAccess)
        }
        .task { await subscriptionAccess.refresh() }
      } else if scenario.hasPrefix("settings-") {
        ConnectionSettingsView(subscriptionAccess: subscriptionAccess, connection: sureConnection,
          analytics: analytics, telemetryBuildDetails: telemetryBuildDetails,
          diagnostics: FixtureDiagnostics())
          .task { await subscriptionAccess.refresh() }
          .preferredColorScheme(scenario == "settings-paid-dark" ? .dark : .light)
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
  private(set) var canLogOut: Bool
  var requiresSecondFactor: Bool
  init(canLogOut: Bool = false, requiresSecondFactor: Bool = false) {
    self.canLogOut = canLogOut
    self.requiresSecondFactor = requiresSecondFactor
  }
  var allowsWalletPreview: Bool { false }
  var connectionID: String? { nil }
  var serverURL: URL? { nil }
  var isOAuthConnected: Bool { false }
  func matchesStoredAPIKey(_ key: String) -> Bool { false }
  func signIn(_ method: AuthenticationMethod, serverURL: String) async {
    switch method {
    case .provider(.google): status = .failed("Google sign-in started in the test fixture.")
    case .provider(.apple): status = .failed("Apple sign-in started in the test fixture.")
    case .passkey: status = .failed("Passkey sign-in started in the test fixture.")
    case .password(_, _, let code):
      status = requiresSecondFactor ? (code == "123456" ? .connected : .requiresSecondFactor) : .connecting
    default: break
    }
  }
  func cancel() { status = .notConnected }
  func cancelOnboarding() {}
  func logOut() async { canLogOut = false; status = .notConnected }
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
  var showInsights = false
  var insightDismissalFailure = false
  var acknowledgedInsights: Set<UUID> = []
  func fetchInsights() async throws -> [BackendInsight] {
    guard showInsights else { return [] }
    return [
      BackendInsight(id: "00000000-0000-4000-8000-000000000601", type: "idle_cash",
        title: "Put idle cash to work", body: "Review your cash allocation.", priority: "medium", status: "active"),
      BackendInsight(id: "00000000-0000-4000-8000-000000000602", type: "budget_on_track",
        title: "Your budget is on track", body: "Spending is within your plan.", priority: "low", status: "active")
    ].filter { !acknowledgedInsights.contains(UUID(uuidString: $0.id)!) }
  }
  func acknowledgeInsight(id: UUID, requiredServerURL: URL?) async throws {
    if insightDismissalFailure { throw SureAPIError.server(500) }
    acknowledgedInsights.insert(id)
  }
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

private struct FixtureInsightNotifications: InsightNotificationControlling {
  func enableInsightNotifications() async -> Bool { false }
  func disableInsightNotifications() async {}
}
