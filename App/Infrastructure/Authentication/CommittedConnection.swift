import Foundation
import Observation

/// Owns committed identity and the atomic transition shared by every sign-in route.
@MainActor
@Observable
final class CommittedConnection {
  private(set) var context: SureRequestContext?
  private(set) var snapshot: StoredCredentialSnapshot
  private(set) var isSignedOut: Bool
  private(set) var generation = 0
  private(set) var hasStoredCredentialIssue: Bool
  private(set) var hasConnectedToSure: Bool
  private let session: SureSession
  private let credentials: any CredentialRepository
  private let preferences: any ConnectionPreferences
  private let verify: (SureRequestContext) async throws -> Void
  private let beginCredentialChange: () async -> Void
  private let endCredentialChange: () async -> Void
  private let lifecycle: any SureConnectionLifecycleHandling
  private let revokeToken: (String, String) async -> Void
  private let gate: BackendAccessGate

  var isConfigured: Bool { !isSignedOut && context != nil }
  var connectionID: String? { isConfigured ? snapshot.session?.connectionID : nil }
  var canLogOut: Bool { hasStoredCredentialIssue || snapshot.session != nil || isConfigured }

  init(initialState: SureConnectionInitialState, session: SureSession,
       credentials: any CredentialRepository, preferences: any ConnectionPreferences,
       verify: @escaping (SureRequestContext) async throws -> Void,
       beginCredentialChange: @escaping () async -> Void,
       endCredentialChange: @escaping () async -> Void,
       lifecycle: any SureConnectionLifecycleHandling, gate: BackendAccessGate,
       revokeToken: @escaping (String, String) async -> Void) {
    context = initialState.requestContext
    snapshot = initialState.credentials
    isSignedOut = initialState.isExplicitlySignedOut
    hasStoredCredentialIssue = initialState.initializationError != nil
    hasConnectedToSure = preferences.hasConnectedToSure() || initialState.requestContext != nil || initialState.isExplicitlySignedOut
    self.session = session
    self.credentials = credentials
    self.preferences = preferences
    self.verify = verify
    self.beginCredentialChange = beginCredentialChange
    self.endCredentialChange = endCredentialChange
    self.lifecycle = lifecycle
    self.gate = gate
    self.revokeToken = revokeToken
    if hasConnectedToSure { preferences.setHasConnectedToSure(true) }
  }

  func commit(_ candidate: StoredAuthenticatedSession, permit: Int) async throws {
    let candidateContext = try candidate.requestContext()
    let wasConfigured = isConfigured
    var prepared = false
    do {
      try gate.validate(permit)
      try Task.checkCancellation()
      try await verify(candidateContext)
      try gate.validate(permit)
      try Task.checkCancellation()
      await lifecycle.prepareForConnectionChange()
      prepared = true
      try gate.validate(permit)
      try Task.checkCancellation()
      await beginCredentialChange()
      let previous: StoredOAuthSession?
      do {
        try gate.validate(permit)
        try Task.checkCancellation()
        previous = (try? credentials.loadCredentials())?.oauthSession
        try credentials.replaceSession(candidate)
        preferences.setServerURL(candidateContext.baseURL.absoluteString)
        preferences.setExplicitlySignedOut(false)
        preferences.setHasConnectedToSure(true)
        await session.replaceContext(with: candidateContext)
      } catch {
        await endCredentialChange()
        throw error
      }
      await endCredentialChange()
      context = candidateContext
      snapshot = StoredCredentialSnapshot(session: candidate)
      isSignedOut = false
      hasStoredCredentialIssue = false
      hasConnectedToSure = true
      generation += 1
      await lifecycle.didCommitConnectionChange()
      await activate()
      if let previous, candidate != .oauth(previous) { await revoke(previous) }
    } catch {
      if prepared {
        if wasConfigured { await activate() }
        else { await lifecycle.didFailConnectionChange() }
      }
      throw error
    }
  }

  func logOut() async throws {
    preferences.setExplicitlySignedOut(true)
    isSignedOut = true
    generation += 1
    await lifecycle.prepareForLogout()
    await beginCredentialChange()
    let current = (try? credentials.loadCredentials()) ?? snapshot
    await session.clearContext()
    context = nil
    if let oauth = current.oauthSession { await revoke(oauth) }
    var failure: Error?
    do { try credentials.replaceSession(nil) }
    catch { failure = error }
    await endCredentialChange()
    snapshot = (try? credentials.loadCredentials())
      ?? (failure == nil ? StoredCredentialSnapshot(session: nil) : current)
    hasStoredCredentialIssue = failure != nil
    lifecycle.didLogOut()
    if let cleanupFailure = lifecycle.dataCleanupFailure {
      hasStoredCredentialIssue = true
      throw cleanupFailure
    }
    if let failure { throw failure }
  }

  func revoke(_ candidate: StoredOAuthSession) async {
    guard candidate.isVerified else { return }
    await revokeToken(candidate.credentials.accessToken, candidate.serverURL.absoluteString)
    if let refresh = candidate.credentials.refreshToken {
      await revokeToken(refresh, candidate.serverURL.absoluteString)
    }
  }

  private func activate() async {
    let lifecycle = lifecycle
    // Once identity has committed, caller cancellation cannot skip lifecycle setup.
    await Task { @MainActor in await lifecycle.didConnect() }.value
  }
}
