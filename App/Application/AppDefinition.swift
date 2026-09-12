import SwiftUI

#if os(iOS)
import UIKit
#endif

@main
struct AppDefinition: App {
  #if os(iOS)
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  #endif

  @State private var connection: SureConnection
  @State private var financeData: FinanceDataStore
  @State private var spendingComparison: SpendingComparisonStore
  @State private var appleCardConnection: AppleCardConnectionStore
  private var notificationManager: NotificationManager
  private var mobileSSOService: MobileSSOAuthService
  private var remoteAssistant: any RemoteAssistantClient
  private var transactionHistoryStoreFactory: TransactionHistoryStoreFactory
  private var localTransactionHistoryStoreFactory: TransactionHistoryStoreFactory

  init() {
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
    let dataTransport = URLSessionHTTPDataTransport(session: URLSession(configuration: configuration))
    let oauthClient = OAuthHTTPClient(
      dataTransport: dataTransport,
      clientIDStore: UserDefaultsOAuthClientIDStore()
    )
    let oauthService = PasskeyOAuthService(oauthClient: oauthClient)
    let mobileSSOClient = MobileSSOHTTPClient(dataTransport: dataTransport)
    let mobileSSOService = MobileSSOAuthService(
      httpClient: mobileSSOClient,
      deviceInformation: MobileDeviceInformationProvider()
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
      lifecycle: lifecycle
    )
    let transport = SureAPITransport(
      session: session,
      dataTransport: dataTransport,
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
    if initialState.isExplicitlySignedOut {
      appleCardConnection.disconnect()
      financeData.disconnect()
    }
    _connection = State(initialValue: connection)
    _financeData = State(initialValue: financeData)
    _spendingComparison = State(initialValue: spendingComparison)
    _appleCardConnection = State(initialValue: appleCardConnection)
    self.notificationManager = notificationManager
    self.mobileSSOService = mobileSSOService
    remoteAssistant = apiClient
    transactionHistoryStoreFactory = TransactionHistoryStoreFactory(
      client: apiClient,
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
    watchInsightsSync.activate()
    #endif
  }

  var body: some Scene {
    WindowGroup {
      ContentView(
        connection: connection,
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
      .onOpenURL { url in
        mobileSSOService.handleOpenURL(url)
      }
    }
  }
}
