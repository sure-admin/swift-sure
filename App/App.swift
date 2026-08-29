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
  private var notificationManager: NotificationManager
  private var remoteAssistant: any RemoteAssistantClient
  private var transactionHistoryStoreFactory: TransactionHistoryStoreFactory

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
    let dataTransport = URLSessionHTTPDataTransport(session: .shared)
    let oauthClient = OAuthHTTPClient(
      dataTransport: dataTransport,
      clientIDStore: UserDefaultsOAuthClientIDStore()
    )
    let oauthService = PasskeyOAuthService(oauthClient: oauthClient)
    let refreshCoordinator = OAuthRefreshCoordinator(
      session: session,
      credentials: credentials,
      tokenRefresher: oauthClient
    )
    let lifecycle = ApplicationConnectionLifecycle()
    let connection = SureConnection(
      initialState: initialState,
      session: session,
      credentials: credentials,
      preferences: preferences,
      oauth: oauthService,
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
    let syncInsights: ([BackendInsight]) -> Void = { insights in
      WatchInsightsSync.shared.send(insights)
    }
    #else
    let syncInsights: ([BackendInsight]) -> Void = { _ in }
    #endif
    let financeData = FinanceDataStore(
      connection: connection,
      client: apiClient,
      calendar: .autoupdatingCurrent,
      now: { .now },
      syncInsights: syncInsights
    )

    lifecycle.notificationLifecycle = notificationManager
    lifecycle.financeData = financeData
    _connection = State(initialValue: connection)
    _financeData = State(initialValue: financeData)
    self.notificationManager = notificationManager
    remoteAssistant = apiClient
    transactionHistoryStoreFactory = TransactionHistoryStoreFactory(
      client: apiClient,
      calendar: .autoupdatingCurrent,
      now: { .now }
    )

    #if os(iOS)
    appDelegate.notificationEventHandler = notificationManager
    WatchInsightsSync.shared.activate()
    #endif
  }

  var body: some Scene {
    WindowGroup {
      ContentView(
        connection: connection,
        financeData: financeData,
        notificationManager: notificationManager,
        remoteAssistant: remoteAssistant,
        transactionHistoryStoreFactory: transactionHistoryStoreFactory
      )
    }
  }
}
