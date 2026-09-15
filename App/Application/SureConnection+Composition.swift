import Foundation

extension SureConnection {
  convenience init(
    initialState: SureConnectionInitialState, session: SureSession,
    credentials: any CredentialRepository, preferences: any ConnectionPreferences,
    oauth: any OAuthAuthenticating, mobileSSO: any MobileSSOAuthenticating,
    verify: @escaping (SureRequestContext) async throws -> Void,
    beginCredentialChange: @escaping () async -> Void,
    endCredentialChange: @escaping () async -> Void,
    lifecycle: any SureConnectionLifecycleHandling,
    accessGate: BackendAccessGate = BackendAccessGate(),
    makeConnectionID: @escaping () -> UUID = { UUID() },
    waitForAuthenticationDeadline: @escaping @Sendable () async throws -> Void = {
      try await Task.sleep(for: .seconds(180))
    }
  ) {
    let committed = CommittedConnection(initialState: initialState, session: session,
      credentials: credentials, preferences: preferences, verify: verify,
      beginCredentialChange: beginCredentialChange, endCredentialChange: endCredentialChange,
      lifecycle: lifecycle, gate: accessGate,
      revokeToken: { token, server in await oauth.revoke(token: token, serverURL: server) })
    self.init(initialState: initialState, authentication: AuthenticationCoordinator(
      connection: committed, oauth: oauth, mobile: mobileSSO, gate: accessGate,
      initializationError: initialState.initializationError, makeConnectionID: makeConnectionID,
      waitForDeadline: waitForAuthenticationDeadline))
  }
}
