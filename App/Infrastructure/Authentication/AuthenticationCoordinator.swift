import Foundation
import Observation

@MainActor
@Observable
final class AuthenticationCoordinator: ConnectionAuthenticating {
  private(set) var status: ConnectionStatus
  private(set) var pendingOnboarding: MobileSSOOnboardingContext?
  let connection: CommittedConnection
  private let oauth: any OAuthAuthenticating
  private let mobile: any MobileSSOAuthenticating
  private let gate: BackendAccessGate
  private let makeConnectionID: () -> UUID
  private let waitForDeadline: @Sendable () async throws -> Void
  private var attempt: Task<Void, Never>?

  init(connection: CommittedConnection, oauth: any OAuthAuthenticating,
       mobile: any MobileSSOAuthenticating, gate: BackendAccessGate,
       initializationError: String? = nil,
       makeConnectionID: @escaping () -> UUID = { UUID() },
       waitForDeadline: @escaping @Sendable () async throws -> Void = {
         try await Task.sleep(for: .seconds(180))
       }) {
    self.connection = connection
    self.oauth = oauth
    self.mobile = mobile
    self.gate = gate
    self.makeConnectionID = makeConnectionID
    self.waitForDeadline = waitForDeadline
    status = initializationError.map(ConnectionStatus.failed)
      ?? (connection.isConfigured ? .connected : .notConnected)
  }

  var isConfigured: Bool { connection.isConfigured }
  var isSignedOut: Bool { connection.isSignedOut }
  var generation: Int { connection.generation }
  var canLogOut: Bool { connection.canLogOut }
  var allowsWalletPreview: Bool { !connection.hasConnectedToSure }
  var connectionID: String? { connection.connectionID }
  var serverURL: URL? { isConfigured ? connection.context?.baseURL : nil }
  var isOAuthConnected: Bool { isConfigured && connection.snapshot.oauthSession != nil }
  func matchesStoredAPIKey(_ key: String) -> Bool { key == connection.snapshot.apiKey }

  func signIn(_ method: AuthenticationMethod, serverURL: String) async {
    guard attempt == nil, status != .connecting, let permit = try? gate.permit() else { return }
    status = .connecting
    let startingGeneration = connection.generation
    var deadlineReached = false
    let task = Task { @MainActor in
      var candidate: StoredAuthenticatedSession?
      do {
        let server = try OAuthServerURL(serverURL.trimmingCharacters(in: .whitespacesAndNewlines))
        candidate = try await authenticate(method, server: server)
        try Task.checkCancellation()
        try gate.validate(permit)
        if let candidate {
          pendingOnboarding = nil
          try await connection.commit(candidate, permit: permit)
        }
        status = stableStatus
      } catch {
        pendingOnboarding = nil
        if case .oauth(let oauth)? = candidate { await connection.revoke(oauth) }
        status = Self.isCancellation(error) ? stableStatus : .failed(Self.safeMessage(error))
      }
    }
    attempt = task
    let wait = waitForDeadline
    let deadline = Task { @MainActor in
      do { try await wait() }
      catch { return }
      if connection.generation == startingGeneration {
        deadlineReached = true
        task.cancel()
      }
    }
    await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    deadline.cancel()
    if deadlineReached { status = .failed("The sign-in timed out. Try again.") }
    attempt = nil
  }

  func cancel() { attempt?.cancel() }
  func cancelOnboarding() { pendingOnboarding = nil }

  func logOut() async {
    if let attempt { attempt.cancel(); await attempt.value; self.attempt = nil }
    status = .connecting
    pendingOnboarding = nil
    do { try await connection.logOut(); status = .notConnected }
    catch { status = .failed(Self.safeMessage(error)) }
  }

  private func authenticate(_ method: AuthenticationMethod, server: OAuthServerURL) async throws -> StoredAuthenticatedSession? {
    switch method {
    case .apiKey(let key):
      return .apiKey(try StoredAPIKeySession(serverURL: server.url,
        apiKey: key.trimmingCharacters(in: .whitespacesAndNewlines), isVerified: true,
        connectionID: makeConnectionID().uuidString))
    case .passkey:
      return try oauthSession(try await oauth.signIn(serverURL: server.url.absoluteString),
        server: server, source: .dynamicClient)
    case .password(let email, let password):
      return try mobileSession(try await mobile.signIn(email: email, password: password,
        serverURL: server.url.absoluteString), server: server)
    case .provider(let provider):
      return try mobileSession(try await mobile.signIn(provider: provider,
        serverURL: server.url.absoluteString), server: server)
    }
  }

  private func mobileSession(_ result: MobileSSOResult, server: OAuthServerURL) throws -> StoredAuthenticatedSession? {
    switch result {
    case .onboarding(let context): pendingOnboarding = context; return nil
    case .authenticated(let tokens, let id): return try oauthSession(tokens, server: server, source: .mobileDevice(deviceID: id))
    }
  }

  private func oauthSession(_ tokens: PasskeyOAuthTokens, server: OAuthServerURL,
                            source: OAuthTokenSource) throws -> StoredAuthenticatedSession {
    .oauth(try StoredOAuthSession(serverURL: server.url,
      credentials: StoredOAuthCredentials(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken),
      isVerified: true, tokenSource: source, connectionID: makeConnectionID().uuidString))
  }

  private var stableStatus: ConnectionStatus { connection.isConfigured ? .connected : .notConnected }

  private static func isCancellation(_ error: Error) -> Bool {
    error is CancellationError || Task.isCancelled || (error as? URLError)?.code == .cancelled
  }

  private static func safeMessage(_ error: Error) -> String {
    switch error {
    case let error as DataFailure: error.localizedDescription
    case let error as SureAPIError: error.localizedDescription
    case let error as PasskeyOAuthError: error.localizedDescription
    case let error as MobileSSOError: error.localizedDescription
    case let error as CredentialRepositoryError: error.localizedDescription
    case let error as SureRequestContextError: error.localizedDescription
    case let error as BackendAccessError: error.localizedDescription
    default: "The Sure connection couldn’t be completed."
    }
  }
}
