import CryptoKit
import Foundation
import Observation

@MainActor
@Observable
final class SureConnection {
  var serverURL: String {
    didSet { updateAPIKeyDraftState() }
  }

  var apiKey: String {
    didSet { updateAPIKeyDraftState() }
  }

  var email: String
  var password: String

  private(set) var isAPIKeyStored: Bool
  private(set) var isSignedOut: Bool
  private(set) var sessionGeneration = 0
  private(set) var pendingSSOOnboarding: MobileSSOOnboardingContext?
  var status: ConnectionStatus

  var isConfigured: Bool {
    !isSignedOut && committedContext != nil
  }

  var isOAuthConnected: Bool {
    guard case .some(.bearer) = committedContext?.authorization else { return false }
    return !isSignedOut
  }

  var connectedServerURL: URL? {
    guard isConfigured else { return nil }
    return committedContext?.baseURL
  }

  var connectedSnapshotIdentity: String? {
    guard isConfigured,
          let authorization = committedContext?.authorization else {
      return nil
    }
    let identitySource: String
    switch authorization {
    case .apiKey(let apiKey):
      identitySource = "api-key:\(apiKey)"
    case .bearer:
      // Device/client IDs identify an installation, not the signed-in person.
      // Bind snapshots to this credential so another login cannot restore them.
      identitySource = "oauth:\(oauthSnapshotIdentitySource):\(storedOAuthSession?.credentials.accessToken ?? "")"
    }
    return Data(SHA256.hash(data: Data(identitySource.utf8))).base64EncodedString()
  }

  var canConnectWithAPIKey: Bool {
    guard !normalizedAPIKey.isEmpty else { return false }
    return (try? candidateContext(authorization: .apiKey(normalizedAPIKey))) != nil
  }

  var canSignInWithPasskey: Bool {
    (try? OAuthServerURL(serverURL.trimmingCharacters(in: .whitespacesAndNewlines))) != nil
  }

  var canSignInWithPassword: Bool {
    !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !password.isEmpty
      && canSignInWithPasskey
  }

  var canLogOut: Bool {
    hasStoredCredentialIssue
      || storedOAuthSession != nil
      || storedAPIKeySession != nil
      || (!isSignedOut && committedContext != nil)
  }

  private var session: SureSession
  private var credentials: any CredentialRepository
  private var preferences: any ConnectionPreferences
  private var oauth: any OAuthAuthenticating
  private var mobileSSO: any MobileSSOAuthenticating
  private var verify: (SureRequestContext) async throws -> Void
  private var beginCredentialChange: () async -> Void
  private var endCredentialChange: () async -> Void
  private var lifecycle: any SureConnectionLifecycleHandling
  private var committedContext: SureRequestContext?
  private var storedOAuthSession: StoredOAuthSession?
  private var storedAPIKeySession: StoredAPIKeySession?
  private var hasStoredCredentialIssue: Bool

  init(
    initialState: SureConnectionInitialState,
    session: SureSession,
    credentials: any CredentialRepository,
    preferences: any ConnectionPreferences,
    oauth: any OAuthAuthenticating,
    mobileSSO: any MobileSSOAuthenticating,
    verify: @escaping (SureRequestContext) async throws -> Void,
    beginCredentialChange: @escaping () async -> Void,
    endCredentialChange: @escaping () async -> Void,
    lifecycle: any SureConnectionLifecycleHandling
  ) {
    serverURL = initialState.serverURL
    apiKey = initialState.isExplicitlySignedOut ? "" : initialState.credentials.apiKey ?? ""
    email = "user@example.com"
    password = "Password1!"
    storedAPIKeySession = initialState.credentials.apiKeySession
    storedOAuthSession = initialState.credentials.oauthSession
    pendingSSOOnboarding = nil
    hasStoredCredentialIssue = initialState.initializationError != nil
    committedContext = initialState.requestContext
    isAPIKeyStored = initialState.credentials.apiKey != nil
    isSignedOut = initialState.isExplicitlySignedOut
    if let initializationError = initialState.initializationError {
      status = .failed(initializationError)
    } else {
      status = initialState.requestContext == nil ? .notConnected : .connected
    }
    self.session = session
    self.credentials = credentials
    self.preferences = preferences
    self.oauth = oauth
    self.mobileSSO = mobileSSO
    self.verify = verify
    self.beginCredentialChange = beginCredentialChange
    self.endCredentialChange = endCredentialChange
    self.lifecycle = lifecycle
  }

  func signInWithPasskey() async {
    guard status != .connecting else { return }
    let stableStatus = connectedOrDisconnectedStatus
    var candidateSession: StoredOAuthSession?
    status = .connecting

    do {
      let server = try OAuthServerURL(serverURL.trimmingCharacters(in: .whitespacesAndNewlines))
      let tokens = try await oauth.signIn(serverURL: server.url.absoluteString)
      let candidate = try oauthCandidate(
        tokens: tokens,
        server: server,
        tokenSource: .dynamicClient
      )
      candidateSession = candidate
      pendingSSOOnboarding = nil
      try await commitOAuthCandidate(candidate, stableStatus: stableStatus)
    } catch {
      if let candidateSession {
        await revoke(candidateSession)
      }
      if Self.isCancellation(error) {
        status = stableStatus
      } else {
        status = .failed(Self.safeMessage(for: error))
      }
    }
  }

  func signInWithPassword() async {
    guard status != .connecting else { return }
    let stableStatus = connectedOrDisconnectedStatus
    var candidateSession: StoredOAuthSession?
    status = .connecting

    do {
      let server = try OAuthServerURL(serverURL.trimmingCharacters(in: .whitespacesAndNewlines))
      let result = try await mobileSSO.signIn(
        email: email.trimmingCharacters(in: .whitespacesAndNewlines),
        password: password,
        serverURL: server.url.absoluteString
      )
      guard case .authenticated(let tokens, let deviceID) = result else {
        throw MobileSSOError.invalidCallback
      }
      let candidate = try oauthCandidate(
        tokens: tokens,
        server: server,
        tokenSource: .mobileDevice(deviceID: deviceID)
      )
      candidateSession = candidate
      pendingSSOOnboarding = nil
      try await commitOAuthCandidate(candidate, stableStatus: stableStatus)
    } catch {
      if let candidateSession { await revoke(candidateSession) }
      status = Self.isCancellation(error) ? stableStatus : .failed(Self.safeMessage(for: error))
    }
  }

  func signIn(with provider: SSOProvider) async {
    guard status != .connecting else { return }
    let stableStatus = connectedOrDisconnectedStatus
    var candidateSession: StoredOAuthSession?
    status = .connecting

    do {
      let server = try OAuthServerURL(serverURL.trimmingCharacters(in: .whitespacesAndNewlines))
      let result = try await mobileSSO.signIn(
        provider: provider,
        serverURL: server.url.absoluteString
      )
      switch result {
      case .authenticated(let tokens, let deviceID):
        let candidate = try oauthCandidate(
          tokens: tokens,
          server: server,
          tokenSource: .mobileDevice(deviceID: deviceID)
        )
        candidateSession = candidate
        pendingSSOOnboarding = nil
        try await commitOAuthCandidate(candidate, stableStatus: stableStatus)
      case .onboarding(let context):
        pendingSSOOnboarding = context
        status = stableStatus
      }
    } catch {
      if let candidateSession {
        await revoke(candidateSession)
      }
      if Self.isCancellation(error) {
        status = stableStatus
      } else {
        status = .failed(Self.safeMessage(for: error))
      }
    }
  }

  func cancelSSOOnboarding() {
    pendingSSOOnboarding = nil
  }

  func connectWithAPIKey() async {
    guard status != .connecting else { return }
    let candidateAPIKey = normalizedAPIKey
    let stableStatus = connectedOrDisconnectedStatus
    var preparedCurrentSession = false
    status = .connecting

    do {
      let context = try candidateContext(authorization: .apiKey(candidateAPIKey))
      let candidate = try StoredAPIKeySession(
        serverURL: context.baseURL,
        apiKey: candidateAPIKey,
        isVerified: true
      )
      try await verify(context)
      try Task.checkCancellation()
      await lifecycle.prepareForConnectionChange()
      preparedCurrentSession = true
      try Task.checkCancellation()
      await beginCredentialChange()
      var previousOAuth: StoredOAuthSession?

      do {
        try Task.checkCancellation()
        previousOAuth = (try? credentials.loadCredentials())?.oauthSession
        try Task.checkCancellation()
        try credentials.replaceSession(.apiKey(candidate))
        preferences.setServerURL(context.baseURL.absoluteString)
        preferences.setExplicitlySignedOut(false)
        await session.replaceContext(with: context)
      } catch {
        await endCredentialChange()
        throw error
      }
      await endCredentialChange()

      storedAPIKeySession = candidate
      storedOAuthSession = nil
      hasStoredCredentialIssue = false
      sessionGeneration += 1
      committedContext = context
      serverURL = context.baseURL.absoluteString
      apiKey = candidateAPIKey
      isSignedOut = false
      updateAPIKeyDraftState()
      status = .connected
      lifecycle.didCommitConnectionChange()
      await activateCommittedSession()

      if let previousOAuth {
        await revoke(previousOAuth)
      }
    } catch {
      if preparedCurrentSession, stableStatus == .connected {
        await activateCommittedSession()
      }
      if Self.isCancellation(error) {
        status = stableStatus
      } else {
        status = .failed(Self.safeMessage(for: error))
      }
    }
  }

  func logOut() async {
    guard status != .connecting else { return }
    status = .connecting
    // Persist the user's intent before any suspension so relaunch is fail-closed.
    preferences.setExplicitlySignedOut(true)
    isSignedOut = true
    pendingSSOOnboarding = nil
    email = ""
    password = ""
    sessionGeneration += 1
    await lifecycle.prepareForLogout()
    await beginCredentialChange()

    let currentCredentials = (try? credentials.loadCredentials())
      ?? StoredCredentialSnapshot(
        session: storedOAuthSession.map(StoredAuthenticatedSession.oauth)
          ?? storedAPIKeySession.map(StoredAuthenticatedSession.apiKey)
      )
    let currentOAuth = currentCredentials.oauthSession
    await session.clearContext()
    committedContext = nil
    if let currentOAuth {
      await revoke(currentOAuth)
    }

    var persistenceError: Error?
    do {
      try credentials.replaceSession(nil)
    } catch {
      persistenceError = error
    }

    await endCredentialChange()
    let remainingCredentials = try? credentials.loadCredentials()
    storedOAuthSession = remainingCredentials?.oauthSession
      ?? (persistenceError == nil ? nil : currentOAuth)
    storedAPIKeySession = remainingCredentials?.apiKeySession
      ?? (persistenceError == nil ? nil : currentCredentials.apiKeySession)
    hasStoredCredentialIssue = persistenceError != nil
    apiKey = ""
    isAPIKeyStored = false
    lifecycle.didLogOut()
    status = persistenceError.map { .failed(Self.safeMessage(for: $0)) } ?? .notConnected
  }

  private var normalizedAPIKey: String {
    apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func oauthCandidate(
    tokens: PasskeyOAuthTokens,
    server: OAuthServerURL,
    tokenSource: OAuthTokenSource
  ) throws -> StoredOAuthSession {
    let credentials = try StoredOAuthCredentials(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken
    )
    return try StoredOAuthSession(
      serverURL: server.url,
      credentials: credentials,
      isVerified: true,
      tokenSource: tokenSource
    )
  }

  private func commitOAuthCandidate(
    _ candidate: StoredOAuthSession,
    stableStatus: ConnectionStatus
  ) async throws {
    let context = try candidate.requestContext()
    var preparedCurrentSession = false
    do {
      try Task.checkCancellation()
      try await verify(context)
      try Task.checkCancellation()
      await lifecycle.prepareForConnectionChange()
      preparedCurrentSession = true
      try Task.checkCancellation()
      await beginCredentialChange()
      var previousOAuth: StoredOAuthSession?
      do {
        try Task.checkCancellation()
        previousOAuth = (try? credentials.loadCredentials())?.oauthSession
        try Task.checkCancellation()
        try credentials.replaceSession(.oauth(candidate))
        preferences.setServerURL(context.baseURL.absoluteString)
        preferences.setExplicitlySignedOut(false)
        await session.replaceContext(with: context)
      } catch {
        await endCredentialChange()
        throw error
      }
      await endCredentialChange()

      committedContext = context
      storedOAuthSession = candidate
      storedAPIKeySession = nil
      hasStoredCredentialIssue = false
      sessionGeneration += 1
      serverURL = context.baseURL.absoluteString
      isSignedOut = false
      status = .connected
      lifecycle.didCommitConnectionChange()
      await activateCommittedSession()

      if let previousOAuth, previousOAuth != candidate {
        await revoke(previousOAuth)
      }
    } catch {
      if preparedCurrentSession, stableStatus == .connected {
        await activateCommittedSession()
      }
      throw error
    }
  }

  private var connectedOrDisconnectedStatus: ConnectionStatus {
    committedContext == nil || isSignedOut ? .notConnected : .connected
  }

  private var oauthSnapshotIdentitySource: String {
    switch storedOAuthSession?.tokenSource {
    case .mobileDevice(let deviceID): "mobile-device:\(deviceID)"
    case .dynamicClient: "dynamic-client"
    case nil: "unknown"
    }
  }

  private func candidateContext(
    authorization: SureRequestAuthorization
  ) throws -> SureRequestContext {
    let value = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: value) else {
      throw SureRequestContextError.invalidBaseURL
    }
    return try SureRequestContext(baseURL: url, authorization: authorization)
  }

  private func updateAPIKeyDraftState() {
    let matchesStoredKey = !normalizedAPIKey.isEmpty
      && normalizedAPIKey == storedAPIKeySession?.apiKey
    isAPIKeyStored = matchesStoredKey
  }

  private var normalizedServerURL: String? {
    guard let context = try? candidateContext(authorization: .apiKey("candidate")) else {
      return nil
    }
    return context.baseURL.absoluteString
  }

  private func revoke(_ session: StoredOAuthSession) async {
    guard session.isVerified else { return }
    await oauth.revoke(
      token: session.credentials.accessToken,
      serverURL: session.serverURL.absoluteString
    )
    if let refreshToken = session.credentials.refreshToken {
      await oauth.revoke(token: refreshToken, serverURL: session.serverURL.absoluteString)
    }
  }

  private func activateCommittedSession() async {
    let lifecycle = lifecycle
    await Task { @MainActor in
      await lifecycle.didConnect()
    }.value
  }

  private static func isCancellation(_ error: Error) -> Bool {
    if error is CancellationError || Task.isCancelled { return true }
    return (error as? URLError)?.code == .cancelled
  }

  private static func safeMessage(for error: Error) -> String {
    switch error {
    case let error as SureAPIError:
      error.localizedDescription
    case let error as PasskeyOAuthError:
      error.localizedDescription
    case let error as MobileSSOError:
      error.localizedDescription
    case let error as CredentialRepositoryError:
      error.localizedDescription
    case let error as SureRequestContextError:
      error.localizedDescription
    default:
      "The Sure connection couldn’t be completed."
    }
  }
}

extension SureConnection: ConnectionStateProviding { }

enum ConnectionStatus: Equatable {
  case notConnected
  case connecting
  case connected
  case failed(String)

  var label: String {
    switch self {
    case .notConnected: "Not connected"
    case .connecting: "Connecting…"
    case .connected: "Connected"
    case .failed: "Connection failed"
    }
  }
}
