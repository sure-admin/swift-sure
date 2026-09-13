import Foundation

protocol UnauthorizedRequestRecovering: Sendable {
  func recoverUnauthorizedRequest(
    for context: SureRequestContext
  ) async throws -> SureRequestContext?
}

actor OAuthRefreshCoordinator: UnauthorizedRequestRecovering {
  private struct CompletedRotation: Equatable {
    var rejectedContext: SureRequestContext
    var refreshedContext: SureRequestContext
  }

  private var session: SureSession
  private var credentials: any CredentialRepository
  private var tokenRefresher: any OAuthTokenRefreshing
  private var inFlightRefresh: Task<SureRequestContext?, Error>?
  private var inFlightContext: SureRequestContext?
  private var completedRotation: CompletedRotation?
  private var isCredentialChangeInProgress = false

  init(
    session: SureSession,
    credentials: any CredentialRepository,
    tokenRefresher: any OAuthTokenRefreshing
  ) {
    self.session = session
    self.credentials = credentials
    self.tokenRefresher = tokenRefresher
  }

  func recoverUnauthorizedRequest(
    for context: SureRequestContext
  ) async throws -> SureRequestContext? {
    guard !isCredentialChangeInProgress else { return nil }
    guard case .some(.bearer) = context.authorization else { return nil }

    if let refreshedContext = await completedRotationContext(for: context) {
      return refreshedContext
    }

    if let inFlightRefresh {
      guard inFlightContext == context else { return nil }
      let refreshedContext = try await inFlightRefresh.value
      return await recordCompletedRotation(
        from: context,
        to: refreshedContext
      )
    }

    guard try await session.requestContext() == context else { return nil }
    guard !isCredentialChangeInProgress else { return nil }

    let repository = credentials
    let refresher = tokenRefresher
    let session = session
    completedRotation = nil
    let task = Task<SureRequestContext?, Error> {
      let snapshot = try repository.loadCredentials()
      guard case .some(.bearer(let rejectedAccessToken)) = context.authorization,
            let oauthSession = snapshot.oauthSession,
            oauthSession.isVerified,
            oauthSession.serverURL == context.baseURL,
            oauthSession.credentials.accessToken == rejectedAccessToken,
            let refreshToken = oauthSession.credentials.refreshToken else {
        return nil
      }

      let tokens = try await refresher.refresh(
        refreshToken: refreshToken,
        serverURL: context.baseURL.absoluteString,
        source: oauthSession.tokenSource
      )
      guard let rotatedRefreshToken = tokens.refreshToken else {
        throw PasskeyOAuthError.invalidResponse
      }
      let rotatedCredentials = try StoredOAuthCredentials(
        accessToken: tokens.accessToken,
        refreshToken: rotatedRefreshToken
      )
      let rotatedSession = try StoredOAuthSession(
        serverURL: oauthSession.serverURL,
        credentials: rotatedCredentials,
        isVerified: true,
        tokenSource: oauthSession.tokenSource,
        connectionID: oauthSession.connectionID
      )
      guard try await session.requestContext() == context else { return nil }

      try repository.replaceSession(.oauth(rotatedSession))
      let refreshedContext = try rotatedSession.requestContext()
      await session.replaceContext(with: refreshedContext)
      return refreshedContext
    }

    inFlightContext = context
    inFlightRefresh = task
    defer {
      inFlightContext = nil
      inFlightRefresh = nil
    }
    let refreshedContext = try await task.value
    return await recordCompletedRotation(
      from: context,
      to: refreshedContext
    )
  }

  /// Establishes an exclusive credential transition after any rotation that
  /// already reached Sure. Unauthorized requests cannot start a new refresh
  /// until `endCredentialChange()` is called.
  func beginCredentialChange() async {
    isCredentialChangeInProgress = true
    completedRotation = nil
    if let inFlightRefresh {
      _ = try? await inFlightRefresh.value
    }
  }

  func endCredentialChange() {
    isCredentialChangeInProgress = false
  }

  private func recordCompletedRotation(
    from rejectedContext: SureRequestContext,
    to refreshedContext: SureRequestContext?
  ) async -> SureRequestContext? {
    guard !isCredentialChangeInProgress, let refreshedContext else {
      return nil
    }
    let currentContext = try? await session.requestContext()
    guard !isCredentialChangeInProgress, currentContext == refreshedContext else {
      return nil
    }
    completedRotation = CompletedRotation(
      rejectedContext: rejectedContext,
      refreshedContext: refreshedContext
    )
    return refreshedContext
  }

  private func completedRotationContext(
    for rejectedContext: SureRequestContext
  ) async -> SureRequestContext? {
    guard let rotation = completedRotation,
          rotation.rejectedContext == rejectedContext else {
      return nil
    }
    let currentContext = try? await session.requestContext()
    guard !isCredentialChangeInProgress,
          completedRotation == rotation,
          currentContext == rotation.refreshedContext else {
      if completedRotation == rotation {
        completedRotation = nil
      }
      return nil
    }
    return rotation.refreshedContext
  }
}
