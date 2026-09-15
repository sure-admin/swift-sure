import Foundation
import Testing
@testable import Sure

@MainActor
@Suite("Sure connection")
struct SureConnectionTests {
  @Test("OAuth snapshots are isolated between logins on the same installation")
  func snapshotIdentityIsolation() throws {
    let first = makeHarness(
      context: try requestContext(server: "https://sure.example", authorization: .bearer("first")),
      oauthCredentials: try StoredOAuthCredentials(accessToken: "first", refreshToken: "refresh-first")
    )
    let second = makeHarness(
      context: try requestContext(server: "https://sure.example", authorization: .bearer("second")),
      oauthCredentials: try StoredOAuthCredentials(accessToken: "second", refreshToken: "refresh-second")
    )
    #expect(first.connection.connectedSnapshotIdentity != nil)
    #expect(first.connection.connectedSnapshotIdentity != second.connection.connectedSnapshotIdentity)
  }

  @Test("Hydration uses the server bound to verified credentials and honors sign-out")
  func hydration() throws {
    let oauthSession = try StoredOAuthSession(
      serverURL: #require(URL(string: "https://bound.sure.example/")),
      credentials: StoredOAuthCredentials(
        accessToken: "stored-access",
        refreshToken: "stored-refresh"
      ),
      isVerified: true
    )
    let credentials = CredentialRepositoryFake(
      snapshot: StoredCredentialSnapshot(session: .oauth(oauthSession))
    )
    let preferences = ConnectionPreferencesFake(
      serverURL: "https://person@wrong.example?token=private"
    )

    let connected = SureConnectionInitialState.load(
      credentials: credentials,
      preferences: preferences
    )
    #expect(connected.requestContext?.baseURL.absoluteString == "https://bound.sure.example")
    #expect(connected.requestContext?.authorization == .bearer("stored-access"))

    preferences.explicitlySignedOut = true
    let signedOut = SureConnectionInitialState.load(
      credentials: credentials,
      preferences: preferences
    )
    #expect(signedOut.requestContext == nil)
    #expect(signedOut.credentials.oauthCredentials?.accessToken == "stored-access")

    preferences.explicitlySignedOut = false
    let reconnected = SureConnectionInitialState.load(
      credentials: credentials,
      preferences: preferences
    )
    #expect(reconnected.requestContext?.baseURL == oauthSession.serverURL)
    #expect(reconnected.initializationError == nil)
  }

  @Test("Unverified migrated credentials never hydrate a request session")
  func unverifiedHydrationIsFailClosed() throws {
    let migrated = try StoredOAuthSession(
      serverURL: #require(URL(string: "https://sure.example")),
      credentials: StoredOAuthCredentials(
        accessToken: "legacy-access",
        refreshToken: "legacy-refresh"
      ),
      isVerified: false
    )
    let state = SureConnectionInitialState.load(
      credentials: CredentialRepositoryFake(
        snapshot: StoredCredentialSnapshot(session: .oauth(migrated))
      ),
      preferences: ConnectionPreferencesFake(serverURL: "https://sure.example")
    )

    #expect(state.requestContext == nil)
    #expect(state.credentials.oauthSession == migrated)
  }

  @Test("An API key is verified as a candidate before replacing the OAuth session")
  func apiKeySuccess() async throws {
    let previousOAuth = try StoredOAuthCredentials(
      accessToken: "old-access",
      refreshToken: "old-refresh"
    )
    let oldContext = try requestContext(
      server: "https://old.sure.example",
      authorization: .bearer("old-access")
    )
    let verifier = VerificationSpy()
    let harness = makeHarness(
      context: oldContext,
      oauthCredentials: previousOAuth,
      verifier: verifier
    )
    harness.connection.serverURL = "https://new.sure.example/"
    harness.connection.apiKey = "  candidate-key\n"

    await harness.connection.connectWithAPIKey()

    #expect(harness.connection.status == .connected)
    #expect(harness.connection.isConfigured)
    #expect(!harness.connection.isOAuthConnected)
    #expect(harness.connection.isAPIKeyStored)
    #expect(harness.credentials.snapshot.apiKey == "candidate-key")
    #expect(harness.credentials.snapshot.isAPIKeyVerified)
    #expect(harness.credentials.snapshot.oauthCredentials == nil)
    #expect(harness.preferences.savedServerURL == "https://new.sure.example")
    #expect(harness.preferences.explicitlySignedOut == false)
    #expect(harness.lifecycle.didConnectCount == 1)
    #expect(harness.lifecycle.events.first == "prepareForConnectionChange")
    #expect(await verifier.contexts == [
      try requestContext(
        server: "https://new.sure.example",
        authorization: .apiKey("candidate-key")
      )
    ])
    #expect(try await harness.session.requestContext().authorization == .apiKey("candidate-key"))
    #expect(harness.oauth.revocations.map(\.token) == ["old-access", "old-refresh"])
  }

  @Test("A rejected API key leaves the previous session and credentials untouched")
  func apiKeyFailureRollback() async throws {
    let oldCredentials = try StoredOAuthCredentials(
      accessToken: "old-access",
      refreshToken: "old-refresh"
    )
    let oldContext = try requestContext(
      server: "https://old.sure.example",
      authorization: .bearer("old-access")
    )
    let verifier = VerificationSpy(error: SureAPIError.unauthorized)
    let harness = makeHarness(
      context: oldContext,
      oauthCredentials: oldCredentials,
      verifier: verifier
    )
    harness.connection.serverURL = "https://new.sure.example"
    harness.connection.apiKey = "rejected-key"

    await harness.connection.connectWithAPIKey()

    #expect(harness.connection.status == .failed("Sure rejected the current credentials."))
    #expect(harness.connection.isConfigured)
    #expect(harness.connection.isOAuthConnected)
    #expect(harness.credentials.snapshot.oauthCredentials == oldCredentials)
    #expect(harness.credentials.snapshot.apiKey == nil)
    #expect(try await harness.session.requestContext() == oldContext)
    #expect(harness.lifecycle.didConnectCount == 0)
    #expect(harness.lifecycle.events.isEmpty)
  }

  @Test("OAuth commits access and refresh together and removes a stale refresh")
  func oauthSuccessWithoutRefreshToken() async throws {
    let oldCredentials = try StoredOAuthCredentials(
      accessToken: "old-access",
      refreshToken: "stale-refresh"
    )
    let oldContext = try requestContext(
      server: "https://old.sure.example",
      authorization: .bearer("old-access")
    )
    let verifier = VerificationSpy()
    let oauth = OAuthAuthenticationFake(
      tokens: PasskeyOAuthTokens(
        accessToken: "new-access",
        refreshToken: nil
      )
    )
    let harness = makeHarness(
      context: oldContext,
      oauthCredentials: oldCredentials,
      oauth: oauth,
      verifier: verifier
    )
    harness.connection.serverURL = "https://new.sure.example/"

    await harness.connection.signInWithPasskey()

    #expect(harness.connection.status == .connected)
    #expect(harness.connection.isOAuthConnected)
    #expect(harness.credentials.snapshot.oauthCredentials?.accessToken == "new-access")
    #expect(harness.credentials.snapshot.oauthCredentials?.refreshToken == nil)
    #expect(try await harness.session.requestContext().authorization == .bearer("new-access"))
    #expect(await verifier.contexts.first?.authorization == .bearer("new-access"))
    #expect(oauth.revocations.map(\.token) == ["old-access", "stale-refresh"])
    #expect(harness.lifecycle.didConnectCount == 1)
  }

  @Test("OAuth persistence failure preserves the prior session and revokes the candidate")
  func oauthPersistenceFailure() async throws {
    let oldCredentials = try StoredOAuthCredentials(
      accessToken: "old-access",
      refreshToken: "old-refresh"
    )
    let oldContext = try requestContext(
      server: "https://old.sure.example",
      authorization: .bearer("old-access")
    )
    let oauth = OAuthAuthenticationFake(
      tokens: PasskeyOAuthTokens(
        accessToken: "candidate-access",
        refreshToken: "candidate-refresh"
      )
    )
    let harness = makeHarness(
      context: oldContext,
      oauthCredentials: oldCredentials,
      oauth: oauth
    )
    harness.credentials.failNextOAuthWrite = true
    harness.connection.serverURL = "https://new.sure.example"

    await harness.connection.signInWithPasskey()

    #expect(
      harness.connection.status
        == .failed("The Sure credentials couldn’t be saved securely.")
    )
    #expect(harness.credentials.snapshot.oauthCredentials == oldCredentials)
    #expect(try await harness.session.requestContext() == oldContext)
    #expect(oauth.revocations.map(\.token) == ["candidate-access", "candidate-refresh"])
    #expect(harness.lifecycle.didConnectCount == 1)
    #expect(harness.lifecycle.events == ["prepareForConnectionChange", "didConnect"])
  }

  @Test("Mobile SSO stores its refresh source and connects the verified session")
  func mobileSSOSuccess() async throws {
    let mobileSSO = MobileSSOAuthenticationFake(result: .authenticated(
      PasskeyOAuthTokens(accessToken: "mobile-access", refreshToken: "mobile-refresh"),
      deviceID: "device-123"
    ))
    let harness = makeHarness(context: nil, mobileSSO: mobileSSO)

    await harness.connection.signIn(with: .google)

    #expect(harness.connection.status == .connected)
    #expect(harness.connection.isConfigured)
    #expect(harness.credentials.snapshot.oauthSession?.tokenSource == .mobileDevice(
      deviceID: "device-123"
    ))
    #expect(mobileSSO.providers == [.google])
  }

  @Test("An unlinked SSO identity hands off to onboarding without inventing a session")
  func mobileSSOOnboarding() async throws {
    let context = MobileSSOOnboardingContext(
      linkingCode: "link-123",
      email: "person@example.com",
      firstName: "Taylor",
      lastName: nil,
      allowsAccountCreation: true,
      hasPendingInvitation: false
    )
    let harness = makeHarness(
      context: nil,
      mobileSSO: MobileSSOAuthenticationFake(result: .onboarding(context))
    )

    await harness.connection.signIn(with: .apple)

    #expect(harness.connection.pendingSSOOnboarding == context)
    #expect(harness.connection.status == .notConnected)
    #expect(!harness.connection.isConfigured)
    #expect(harness.credentials.snapshot.session == nil)
  }

  @Test("Passkey authentication clears an unlinked SSO handoff")
  func passkeyClearsMobileSSOOnboarding() async throws {
    let onboarding = MobileSSOOnboardingContext(
      linkingCode: "link-123",
      email: "person@example.com",
      firstName: nil,
      lastName: nil,
      allowsAccountCreation: false,
      hasPendingInvitation: false
    )
    let harness = makeHarness(
      context: nil,
      oauth: OAuthAuthenticationFake(tokens: PasskeyOAuthTokens(
        accessToken: "passkey-access",
        refreshToken: "passkey-refresh"
      )),
      mobileSSO: MobileSSOAuthenticationFake(result: .onboarding(onboarding))
    )

    await harness.connection.signIn(with: .google)
    await harness.connection.signInWithPasskey()

    #expect(harness.connection.pendingSSOOnboarding == nil)
    #expect(harness.connection.isConfigured)
    #expect(harness.connection.status == .connected)
  }

  @Test("Cancellation restores the prior stable state without persisting or reporting failure")
  func cancellation() async throws {
    let context = try requestContext(
      server: "https://sure.example",
      authorization: .apiKey("working-key")
    )
    let harness = makeHarness(
      context: context,
      apiKey: "working-key",
      isAPIKeyVerified: true,
      oauth: OAuthAuthenticationFake(error: CancellationError())
    )

    await harness.connection.signInWithPasskey()

    #expect(harness.connection.status == .connected)
    #expect(try await harness.session.requestContext() == context)
    #expect(harness.credentials.snapshot.apiKey == "working-key")
    #expect(harness.lifecycle.didConnectCount == 0)
  }

  @Test("Cancellation during lifecycle cleanup cannot commit a candidate session")
  func cancellationDuringLifecycleCleanup() async throws {
    let oldContext = try requestContext(
      server: "https://old.sure.example",
      authorization: .apiKey("old-key")
    )
    let lifecycle = ConnectionLifecycleSpy()
    lifecycle.suspendsConnectionPreparation = true
    let harness = makeHarness(
      context: oldContext,
      apiKey: "old-key",
      isAPIKeyVerified: true,
      lifecycle: lifecycle
    )
    harness.connection.serverURL = "https://new.sure.example"
    harness.connection.apiKey = "candidate-key"

    let task = Task { @MainActor in
      await harness.connection.connectWithAPIKey()
    }
    await lifecycle.waitUntilConnectionPreparationStarted()
    task.cancel()
    lifecycle.resumeConnectionPreparation()
    await task.value

    #expect(harness.connection.status == .connected)
    #expect(harness.credentials.snapshot.apiKey == "old-key")
    #expect(try await harness.session.requestContext() == oldContext)
    #expect(lifecycle.events == ["prepareForConnectionChange", "didConnect"])
  }

  @Test("Cancellation while acquiring credential exclusion cannot commit a candidate session")
  func cancellationWhileAcquiringCredentialExclusion() async throws {
    let oldContext = try requestContext(
      server: "https://old.sure.example",
      authorization: .apiKey("old-key")
    )
    let gate = CredentialChangeGate()
    let harness = makeHarness(
      context: oldContext,
      apiKey: "old-key",
      isAPIKeyVerified: true,
      beginCredentialChange: { await gate.begin() },
      endCredentialChange: { gate.end() }
    )
    harness.connection.serverURL = "https://new.sure.example"
    harness.connection.apiKey = "candidate-key"

    let task = Task { @MainActor in
      await harness.connection.connectWithAPIKey()
    }
    await gate.waitUntilStarted()
    task.cancel()
    gate.resume()
    await task.value

    #expect(harness.connection.status == .connected)
    #expect(harness.credentials.snapshot.apiKey == "old-key")
    #expect(try await harness.session.requestContext() == oldContext)
    #expect(gate.endCount == 1)
    #expect(harness.lifecycle.events == ["prepareForConnectionChange", "didConnect"])
  }

  @Test("Logout performs remote cleanup before clearing all local state")
  func logout() async throws {
    let oauthCredentials = try StoredOAuthCredentials(
      accessToken: "access-token",
      refreshToken: "refresh-token"
    )
    let context = try requestContext(
      server: "https://sure.example",
      authorization: .bearer("access-token")
    )
    let harness = makeHarness(
      context: context,
      oauthCredentials: oauthCredentials
    )

    await harness.connection.logOut()

    #expect(harness.connection.status == .notConnected)
    #expect(!harness.connection.isConfigured)
    #expect(harness.connection.apiKey.isEmpty)
    #expect(harness.credentials.snapshot.oauthCredentials == nil)
    #expect(harness.credentials.snapshot.apiKey == nil)
    #expect(harness.preferences.explicitlySignedOut)
    #expect(harness.lifecycle.events == ["prepareForLogout", "didLogOut"])
    #expect(harness.oauth.revocations.map(\.token) == ["access-token", "refresh-token"])
    do {
      _ = try await harness.session.requestContext()
      #expect(Bool(false))
    } catch let error as SureSessionError {
      #expect(error == .notConfigured)
    }
  }

  @Test("A verified replacement recovers from corrupt saved credentials")
  func replacementRecoversCorruptStorage() async throws {
    let harness = makeHarness(context: nil, credentialLoadFails: true)
    #expect(harness.connection.canLogOut)
    harness.connection.serverURL = "https://sure.example"
    harness.connection.apiKey = "replacement-key"

    await harness.connection.connectWithAPIKey()

    #expect(harness.connection.status == .connected)
    #expect(harness.credentials.snapshot.apiKey == "replacement-key")
    #expect(!harness.credentials.loadFails)
  }

  @Test("Locked access prevents every sign-in method and still permits logout")
  func subscriptionGateBlocksAuthentication() async throws {
    let gate = BackendAccessGate()
    let verifier = VerificationSpy()
    let mobile = MobileSSOAuthenticationFake()
    let harness = makeHarness(context: nil, accessGate: gate, mobileSSO: mobile, verifier: verifier)
    harness.connection.apiKey = "test-key"
    harness.connection.email = "test@example.com"
    harness.connection.password = "test-password"
    await harness.connection.connectWithAPIKey()
    await harness.connection.signInWithPassword()
    await harness.connection.signInWithPasskey()
    await harness.connection.signIn(with: .apple)
    #expect(harness.oauth.signInServerURLs.isEmpty)
    #expect(mobile.providers.isEmpty)
    #expect(await verifier.contexts.isEmpty)
    #expect(!harness.connection.isConfigured)
    await harness.connection.logOut()
    #expect(harness.connection.isSignedOut)
  }

  @Test("Wallet preview ends permanently after the first committed connection")
  func onboardingPreviewBoundary() async {
    let harness = makeHarness(context: nil)
    #expect(harness.connection.allowsWalletPreview)
    harness.connection.apiKey = "test-key"
    await harness.connection.connectWithAPIKey()
    #expect(!harness.connection.allowsWalletPreview)
    #expect(harness.preferences.hasConnectedToSure())
    await harness.connection.logOut()
    #expect(!harness.connection.allowsWalletPreview)
    #expect(harness.preferences.hasConnectedToSure())
  }

  @Test("The cancel intent discards a verified candidate before it commits")
  func cancelIntent() async {
    let lifecycle = ConnectionLifecycleSpy()
    lifecycle.suspendsConnectionPreparation = true
    let harness = makeHarness(context: nil, lifecycle: lifecycle)
    harness.connection.apiKey = "candidate"
    let task = Task { await harness.connection.connectWithAPIKey() }
    await lifecycle.waitUntilConnectionPreparationStarted()
    harness.connection.cancelAuthentication()
    lifecycle.resumeConnectionPreparation()
    await task.value
    #expect(!harness.connection.isConfigured)
    #expect(harness.connection.status == .notConnected)
    #expect(harness.credentials.snapshot.session == nil)
  }

  @Test("Logout reports a failed disk cleanup while keeping the session signed out")
  func logoutCleanupFailure() async {
    let lifecycle = ConnectionLifecycleSpy()
    lifecycle.dataCleanupFailure = .cleanup
    let harness = makeHarness(context: nil, lifecycle: lifecycle)
    await harness.connection.logOut()
    #expect(harness.connection.isSignedOut)
    #expect(!harness.connection.isConfigured)
    #expect(harness.connection.status == .failed(DataFailure.cleanup.localizedDescription))
    #expect(harness.connection.canLogOut)
    lifecycle.dataCleanupFailure = nil
    await harness.connection.logOut()
    #expect(harness.connection.status == .notConnected)
  }

  private func makeHarness(
    context: SureRequestContext?,
    accessGate: BackendAccessGate? = nil,
    oauthCredentials: StoredOAuthCredentials? = nil,
    apiKey: String? = nil,
    isAPIKeyVerified: Bool = false,
    credentialLoadFails: Bool = false,
    oauth: OAuthAuthenticationFake? = nil,
    mobileSSO suppliedMobileSSO: MobileSSOAuthenticationFake? = nil,
    verifier: VerificationSpy = VerificationSpy(),
    lifecycle suppliedLifecycle: ConnectionLifecycleSpy? = nil,
    beginCredentialChange: @escaping () async -> Void = { },
    endCredentialChange: @escaping () async -> Void = { }
  ) -> ConnectionHarness {
    let oauth = oauth ?? OAuthAuthenticationFake(
      tokens: PasskeyOAuthTokens(accessToken: "new-access", refreshToken: "new-refresh")
    )
    let mobileSSO = suppliedMobileSSO ?? MobileSSOAuthenticationFake()
    let baseURL = context?.baseURL ?? URL(string: "https://sure.example")!
    let storedSession: StoredAuthenticatedSession?
    if let oauthCredentials,
       let oauthSession = try? StoredOAuthSession(
         serverURL: baseURL,
         credentials: oauthCredentials,
         isVerified: true
       ) {
      storedSession = .oauth(oauthSession)
    } else if let apiKey,
              let apiKeySession = try? StoredAPIKeySession(
                serverURL: baseURL,
                apiKey: apiKey,
                isVerified: isAPIKeyVerified
              ) {
      storedSession = .apiKey(apiKeySession)
    } else {
      storedSession = nil
    }
    let snapshot = StoredCredentialSnapshot(session: storedSession)
    let credentials = CredentialRepositoryFake(snapshot: snapshot)
    credentials.loadFails = credentialLoadFails
    let preferences = ConnectionPreferencesFake(
      serverURL: context?.baseURL.absoluteString ?? "https://sure.example"
    )
    let lifecycle = suppliedLifecycle ?? ConnectionLifecycleSpy()
    let session = SureSession(context: context)
    let initialState = SureConnectionInitialState(
      serverURL: preferences.savedServerURL,
      credentials: snapshot,
      isExplicitlySignedOut: false,
      requestContext: context,
      initializationError: credentialLoadFails
        ? CredentialRepositoryError.invalidStoredCredentials.localizedDescription
        : nil
    )
    let connection = SureConnection(
      initialState: initialState,
      session: session,
      credentials: credentials,
      preferences: preferences,
      oauth: oauth,
      mobileSSO: mobileSSO,
      verify: { context in try await verifier.verify(context) },
      beginCredentialChange: beginCredentialChange,
      endCredentialChange: endCredentialChange,
      lifecycle: lifecycle,
      accessGate: accessGate ?? entitledTestGate()
    )
    return ConnectionHarness(
      connection: connection,
      session: session,
      credentials: credentials,
      preferences: preferences,
      oauth: oauth,
      lifecycle: lifecycle
    )
  }

  private func requestContext(
    server: String,
    authorization: SureRequestAuthorization
  ) throws -> SureRequestContext {
    try SureRequestContext(
      baseURL: #require(URL(string: server)),
      authorization: authorization
    )
  }
}

@MainActor
private struct ConnectionHarness {
  var connection: SureConnection
  var session: SureSession
  var credentials: CredentialRepositoryFake
  var preferences: ConnectionPreferencesFake
  var oauth: OAuthAuthenticationFake
  var lifecycle: ConnectionLifecycleSpy
}

private final class CredentialRepositoryFake: CredentialRepository, @unchecked Sendable {
  var snapshot: StoredCredentialSnapshot
  var failNextOAuthWrite = false
  var failNextAPIKeyWrite = false
  var loadFails = false

  init(
    snapshot: StoredCredentialSnapshot = StoredCredentialSnapshot(
      session: nil
    )
  ) {
    self.snapshot = snapshot
  }

  func loadCredentials() throws -> StoredCredentialSnapshot {
    if loadFails { throw CredentialRepositoryError.invalidStoredCredentials }
    return snapshot
  }

  func replaceSession(_ session: StoredAuthenticatedSession?) throws {
    if failNextOAuthWrite || failNextAPIKeyWrite {
      failNextOAuthWrite = false
      failNextAPIKeyWrite = false
      throw CredentialRepositoryError.persistenceFailed
    }
    snapshot = StoredCredentialSnapshot(session: session)
    loadFails = false
  }
}

private final class ConnectionPreferencesFake: ConnectionPreferences, @unchecked Sendable {
  var savedServerURL: String
  var explicitlySignedOut: Bool
  var hasConnected = false
  func hasConnectedToSure() -> Bool { hasConnected }
  func setHasConnectedToSure(_ connected: Bool) { hasConnected = connected }

  init(serverURL: String, explicitlySignedOut: Bool = false) {
    savedServerURL = serverURL
    self.explicitlySignedOut = explicitlySignedOut
  }

  func serverURL() -> String? { savedServerURL }
  func setServerURL(_ serverURL: String) { savedServerURL = serverURL }
  func isExplicitlySignedOut() -> Bool { explicitlySignedOut }
  func setExplicitlySignedOut(_ isSignedOut: Bool) { explicitlySignedOut = isSignedOut }
}

@MainActor
private final class OAuthAuthenticationFake: OAuthAuthenticating {
  struct Revocation: Equatable {
    var token: String
    var serverURL: String
  }

  var tokens: PasskeyOAuthTokens?
  var error: Error?
  private(set) var signInServerURLs: [String] = []
  private(set) var revocations: [Revocation] = []

  init(tokens: PasskeyOAuthTokens? = nil, error: Error? = nil) {
    self.tokens = tokens
    self.error = error
  }

  convenience init(error: Error) {
    self.init(tokens: nil, error: error)
  }

  func signIn(serverURL: String) async throws -> PasskeyOAuthTokens {
    signInServerURLs.append(serverURL)
    if let error { throw error }
    return try #require(tokens)
  }

  func revoke(token: String, serverURL: String) async {
    revocations.append(Revocation(token: token, serverURL: serverURL))
  }
}

@MainActor
private final class MobileSSOAuthenticationFake: MobileSSOAuthenticating {
  var result: MobileSSOResult?
  var error: Error?
  private(set) var providers: [SSOProvider] = []

  init(result: MobileSSOResult? = nil, error: Error? = nil) {
    self.result = result
    self.error = error
  }

  func signIn(
    provider: SSOProvider,
    serverURL: String
  ) async throws -> MobileSSOResult {
    providers.append(provider)
    if let error { throw error }
    return try #require(result)
  }
}

private actor VerificationSpy {
  var contexts: [SureRequestContext] = []
  var error: Error?

  init(error: Error? = nil) {
    self.error = error
  }

  func verify(_ context: SureRequestContext) throws {
    contexts.append(context)
    if let error { throw error }
  }
}

@MainActor
private final class ConnectionLifecycleSpy: SureConnectionLifecycleHandling {
  var dataCleanupFailure: DataFailure?
  private(set) var didConnectCount = 0
  private(set) var events: [String] = []
  var suspendsConnectionPreparation = false
  private var didStartConnectionPreparation = false
  private var connectionPreparationContinuation: CheckedContinuation<Void, Never>?
  private var connectionPreparationWaiters: [CheckedContinuation<Void, Never>] = []

  func didConnect() async {
    didConnectCount += 1
    events.append("didConnect")
  }

  func prepareForConnectionChange() async {
    events.append("prepareForConnectionChange")
    guard suspendsConnectionPreparation else { return }
    didStartConnectionPreparation = true
    let waiters = connectionPreparationWaiters
    connectionPreparationWaiters.removeAll()
    waiters.forEach { $0.resume() }
    await withCheckedContinuation { continuation in
      connectionPreparationContinuation = continuation
    }
  }

  func prepareForLogout() async {
    events.append("prepareForLogout")
  }

  func didLogOut() {
    events.append("didLogOut")
  }

  func waitUntilConnectionPreparationStarted() async {
    guard !didStartConnectionPreparation else { return }
    await withCheckedContinuation { continuation in
      connectionPreparationWaiters.append(continuation)
    }
  }

  func resumeConnectionPreparation() {
    connectionPreparationContinuation?.resume()
    connectionPreparationContinuation = nil
  }
}

@MainActor
private final class CredentialChangeGate {
  private(set) var endCount = 0
  private var didStart = false
  private var continuation: CheckedContinuation<Void, Never>?
  private var startWaiters: [CheckedContinuation<Void, Never>] = []

  func begin() async {
    didStart = true
    let waiters = startWaiters
    startWaiters.removeAll()
    waiters.forEach { $0.resume() }
    await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
  }

  func end() {
    endCount += 1
  }

  func waitUntilStarted() async {
    guard !didStart else { return }
    await withCheckedContinuation { continuation in
      startWaiters.append(continuation)
    }
  }

  func resume() {
    continuation?.resume()
    continuation = nil
  }
}
