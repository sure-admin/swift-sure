import SwiftUI

#if os(iOS)
import UIKit
#endif

@main
struct AppDefinition: App {
  #if os(iOS)
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  #endif

  @State private var subscriptionAccess: SubscriptionAccessStore
  @Environment(\.scenePhase) private var scenePhase
  @State private var connection: SureConnection
  @State private var financeData: FinanceDataStore
  @State private var spendingComparison: SpendingComparisonStore
  @State private var appleCardConnection: AppleCardConnectionStore
  private var analytics: AnalyticsStore
  private var notificationManager: NotificationManager
  private var oauthService: PasskeyOAuthService
  private var mobileSSOService: MobileSSOAuthService
  private var remoteAssistant: any RemoteAssistantClient
  private var transactionHistoryStoreFactory: TransactionHistoryStoreFactory
  private var localTransactionHistoryStoreFactory: TransactionHistoryStoreFactory

  init() {
    let analyticsClient: (any AnalyticsClient)?
    #if os(iOS)
    // Test hosts must not start SDK networking, even with a persisted preference.
    if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
       let configuration = PostHogConfiguration(bundle: .main) {
      analyticsClient = PostHogAnalyticsClient(configuration: configuration)
    } else {
      analyticsClient = nil
    }
    #else
    analyticsClient = nil
    #endif
    let analytics = AnalyticsStore(
      preferences: UserDefaultsAnalyticsPreferences(defaults: .standard),
      client: analyticsClient
    )
    self.analytics = analytics
    analytics.capture(.appOpened)
    let preferences = UserDefaultsConnectionPreferences()
    let credentials = KeychainCredentialRepository(
      legacyServerURL: preferences.serverURL() ?? SureConnectionInitialState.defaultServerURL
    )
    let initialState = SureConnectionInitialState.load(
      credentials: credentials,
      preferences: preferences
    )
    let session = SureSession(context: initialState.requestContext)
    // Financial responses must never survive a credential change in an HTTP cache.
    URLCache.shared.removeAllCachedResponses()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    let accessGate = BackendAccessGate()
    let subscriptionAccess = SubscriptionAccessStore(service: StoreKitSubscriptionService(), gate: accessGate) { end in
      try await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
    }
    _subscriptionAccess = State(initialValue: subscriptionAccess)
    let dataTransport = SubscriptionHTTPDataTransport(
      base: URLSessionHTTPDataTransport(session: URLSession(configuration: configuration)), gate: accessGate
    )
    let oauthClient = OAuthHTTPClient(
      dataTransport: dataTransport,
      clientIDStore: UserDefaultsOAuthClientIDStore()
    )
    let oauthService = PasskeyOAuthService(oauthClient: oauthClient, accessGate: accessGate)
    let mobileSSOClient = MobileSSOHTTPClient(dataTransport: dataTransport)
    let mobileSSOService = MobileSSOAuthService(
      httpClient: mobileSSOClient,
      deviceInformation: MobileDeviceInformationProvider(),
      accessGate: accessGate
    )
    let refreshCoordinator = OAuthRefreshCoordinator(
      session: session,
      credentials: credentials,
      tokenRefresher: OAuthTokenRefreshService(
        oauthClient: oauthClient,
        mobileClient: mobileSSOClient
      )
    )
    let lifecycle = ApplicationConnectionLifecycle()
    lifecycle.analytics = analytics
    let connection = SureConnection(
      initialState: initialState,
      session: session,
      credentials: credentials,
      preferences: preferences,
      oauth: oauthService,
      mobileSSO: mobileSSOService,
      verify: { context in
        let transport = SureAPITransport(
          baseURL: context.baseURL,
          dataTransport: dataTransport,
          authorizer: SureConnectionRequestAuthorizer(
            authorization: context.authorization
          )
        )
        try await AccountsAPIClient(transport: transport).verifyAccess()
      },
      beginCredentialChange: {
        await refreshCoordinator.beginCredentialChange()
      },
      endCredentialChange: {
        await refreshCoordinator.endCredentialChange()
      },
      lifecycle: lifecycle,
      accessGate: accessGate
    )
    let offlineResponses = OfflineAPIResponseStore(directory:
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("am.sure.insights/offline-responses", isDirectory: true))
    lifecycle.clearOfflineResponses = { try? await offlineResponses.removeAll() }
    let offlineTransport = OfflineSubscriptionDataTransport(
      base: dataTransport, gate: accessGate, cache: offlineResponses,
      identity: { @MainActor [weak connection] in
        guard let connection, let server = connection.connectedServerURL,
              let identity = connection.connectedSnapshotIdentity else { return nil }
        return server.absoluteString + "\n" + identity
      })
    let transport = SureAPITransport(
      session: session,
      dataTransport: offlineTransport,
      unauthorizedRecovery: refreshCoordinator
    )
    let apiClient = SureAPIClient(transport: transport)
    let notificationManager = NotificationManager(
      currentServerURL: {
        let context = try? await session.requestContext()
        return context?.baseURL
      },
      pushSubscriptions: PushSubscriptionOperations(
        register: { token, environment in
          try await apiClient.registerPushSubscription(
            token: token,
            environment: environment
          )
        },
        unregister: { identifier in
          try await apiClient.unregisterPushSubscription(id: identifier)
        }
      ),
      authorization: SystemNotificationAuthorizationProvider(),
      remoteRegistration: SystemRemoteNotificationRegistrar(),
      storage: LiveNotificationStateStore(),
      environment: { .current }
    )
    #if os(iOS)
    let watchInsightsSync = WatchInsightsSync(
      transport: WatchConnectivityInsightsSender(),
      now: { .now }
    )
    let syncInsights: ([BackendInsight]) -> Void = { insights in
      watchInsightsSync.send(insights)
    }
    #else
    let syncInsights: ([BackendInsight]) -> Void = { _ in }
    #endif
    let financeData = FinanceDataStore(
      connection: connection,
      client: apiClient,
      calendar: .autoupdatingCurrent,
      now: { .now },
      canSync: { accessGate.isAllowed },
      syncInsights: syncInsights,
      snapshotCache: FileFinanceDataSnapshotCache(),
      snapshotServerURL: { [weak connection] in
        connection?.connectedServerURL
      },
      snapshotConnectionIdentity: { [weak connection] in
        connection?.connectedSnapshotIdentity
      }
    )
    let financeKitConnector = FinanceKitAppleCardConnector(calendar: .autoupdatingCurrent)
    let appleCardConnection = AppleCardConnectionStore(
      connector: financeKitConnector,
      requiresReconnect: preferences.requiresWalletReconnect(),
      setRequiresReconnect: preferences.setRequiresWalletReconnect
    )

    let spendingComparison = SpendingComparisonStore(
      client: UnavailableSpendingComparisonClient(),
      connection: connection,
      calendar: .autoupdatingCurrent,
      now: { .now },
      walletClient: WalletSpendingComparisonClient(
        transactions: financeKitConnector, calendar: .autoupdatingCurrent, now: { .now }
      ),
      walletAccess: appleCardConnection
    )

    lifecycle.notificationLifecycle = notificationManager
    lifecycle.financeData = financeData
    lifecycle.spendingComparison = spendingComparison
    lifecycle.appleCardConnection = appleCardConnection
    lifecycle.restoreInitialState(isExplicitlySignedOut: initialState.isExplicitlySignedOut)
    _connection = State(initialValue: connection)
    _financeData = State(initialValue: financeData)
    _spendingComparison = State(initialValue: spendingComparison)
    _appleCardConnection = State(initialValue: appleCardConnection)
    self.notificationManager = notificationManager
    self.mobileSSOService = mobileSSOService
    self.oauthService = oauthService
    remoteAssistant = apiClient
    transactionHistoryStoreFactory = TransactionHistoryStoreFactory(
      client: ArchivedTransactionHistoryClient(base: apiClient, gate: accessGate,
        archive: offlineResponses, identity: { [weak connection] in
          guard let server = connection?.connectedServerURL,
                let identity = connection?.connectedSnapshotIdentity else { return nil }
          return (server, identity)
        }, now: { .now }),
      isOffline: { !accessGate.isAllowed },
      calendar: .autoupdatingCurrent,
      now: { .now }
    )
    localTransactionHistoryStoreFactory = TransactionHistoryStoreFactory(
      client: financeKitConnector,
      calendar: .autoupdatingCurrent,
      now: { .now }
    )

    lifecycle.transactionHistoryFactories = [
      transactionHistoryStoreFactory, localTransactionHistoryStoreFactory
    ]

    #if os(iOS)
    appDelegate.notificationEventHandler = notificationManager
    appDelegate.canReceiveBackendNotifications = { accessGate.isAllowed }
    watchInsightsSync.activate()
    #endif
  }

  var body: some Scene {
    WindowGroup {
      ContentView(
        subscriptionAccess: subscriptionAccess,
        connection: connection,
        analytics: analytics,
        financeData: financeData,
        spendingComparison: spendingComparison,
        appleCardConnection: appleCardConnection,
        notificationManager: notificationManager,
        remoteAssistant: remoteAssistant,
        transactionHistoryStoreFactory: transactionHistoryStoreFactory,
        localTransactionHistoryStoreFactory: localTransactionHistoryStoreFactory,
        makeAssistantMessageID: { UUID() },
        now: { .now }
      )
      .task { await subscriptionAccess.monitor() }
      .onChange(of: scenePhase) { _, phase in
        if phase == .active { Task { await subscriptionAccess.refresh() } }
      }
      .onChange(of: subscriptionAccess.hasAccess) { _, allowed in
        if allowed { Task {
          await financeData.refresh()
          await notificationManager.applicationDidFinishLaunching()
          await notificationManager.didConnect()
        } }
        else {
          connection.suspendAuthentication()
          oauthService.cancelAuthentication()
          mobileSSOService.cancelAuthentication()
        }
      }
      .onOpenURL { url in
        guard subscriptionAccess.hasAccess else { return }
        mobileSSOService.handleOpenURL(url)
      }
    }
  }
}
