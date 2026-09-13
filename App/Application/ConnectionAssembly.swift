import Foundation

@MainActor
struct ConnectionAssembly {
  let preferences: UserDefaultsConnectionPreferences
  let initialState: SureConnectionInitialState
  let session: SureSession
  let accessGate: BackendAccessGate
  let subscriptionAccess: SubscriptionAccessStore
  let oauthService: PasskeyOAuthService
  let mobileSSOService: MobileSSOAuthService
  let lifecycle: ApplicationConnectionLifecycle
  let connection: SureConnection
  let transport: SureAPITransport
  let apiClient: SureAPIClient

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
    let accessGate = BackendAccessGate()
    let subscriptionAccess = SubscriptionAccessStore(service: StoreKitSubscriptionService(), gate: accessGate) { end in
      try await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
    }
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
    let transport = SureAPITransport(
      session: session,
      dataTransport: dataTransport,
      unauthorizedRecovery: refreshCoordinator
    )
    let apiClient = SureAPIClient(transport: transport)
    self.preferences = preferences
    self.initialState = initialState
    self.session = session
    self.accessGate = accessGate
    self.subscriptionAccess = subscriptionAccess
    self.oauthService = oauthService
    self.mobileSSOService = mobileSSOService
    self.lifecycle = lifecycle
    self.connection = connection
    self.transport = transport
    self.apiClient = apiClient
  }
}
