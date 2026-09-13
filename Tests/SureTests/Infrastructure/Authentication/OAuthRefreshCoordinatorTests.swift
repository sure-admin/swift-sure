import Foundation
import Testing
@testable import Sure

@Suite("OAuth refresh coordinator")
struct OAuthRefreshCoordinatorTests {
  @Test("Concurrent unauthorized requests share one refresh and one atomic rotation")
  func singleFlightRotation() async throws {
    let oldCredentials = try StoredOAuthCredentials(
      accessToken: "expired-access",
      refreshToken: "old-refresh"
    )
    let rejectedContext = try SureRequestContext(
      baseURL: #require(URL(string: "https://sure.example")),
      authorization: .bearer("expired-access")
    )
    let session = SureSession(context: rejectedContext)
    let repository = RefreshRepositoryFake(
      session: try StoredOAuthSession(
        serverURL: rejectedContext.baseURL,
        credentials: oldCredentials,
        isVerified: true
      )
    )
    let originalIdentity = try repository.loadCredentials().session?.connectionID
    let refresher = SuspendedOAuthTokenRefresher()
    let coordinator = OAuthRefreshCoordinator(
      session: session,
      credentials: repository,
      tokenRefresher: refresher
    )

    let first = Task {
      try await coordinator.recoverUnauthorizedRequest(for: rejectedContext)
    }
    await refresher.waitUntilStarted()
    let second = Task {
      try await coordinator.recoverUnauthorizedRequest(for: rejectedContext)
    }
    await Task.yield()

    #expect(await refresher.callCount == 1)
    await refresher.complete(with: PasskeyOAuthTokens(
      accessToken: "rotated-access",
      refreshToken: "rotated-refresh"
    ))
    let firstContext = try await first.value
    let secondContext = try await second.value

    #expect(firstContext == secondContext)
    #expect(firstContext?.authorization == .bearer("rotated-access"))
    #expect(repository.credentials?.accessToken == "rotated-access")
    #expect(repository.credentials?.refreshToken == "rotated-refresh")
    #expect(try repository.loadCredentials().session?.connectionID == originalIdentity)
    #expect(try await session.requestContext() == firstContext)
    #expect(await refresher.callCount == 1)
  }

  @Test("API keys and OAuth sessions without refresh tokens do not refresh")
  func ineligibleCredentials() async throws {
    let apiContext = try SureRequestContext(
      baseURL: #require(URL(string: "https://sure.example")),
      authorization: .apiKey("api-key")
    )
    let apiSession = SureSession(context: apiContext)
    let refresher = SuspendedOAuthTokenRefresher()
    let apiCoordinator = OAuthRefreshCoordinator(
      session: apiSession,
      credentials: RefreshRepositoryFake(session: nil),
      tokenRefresher: refresher
    )
    #expect(try await apiCoordinator.recoverUnauthorizedRequest(for: apiContext) == nil)

    let bearerContext = try SureRequestContext(
      baseURL: #require(URL(string: "https://sure.example")),
      authorization: .bearer("access-only")
    )
    let bearerSession = SureSession(context: bearerContext)
    let bearerCoordinator = OAuthRefreshCoordinator(
      session: bearerSession,
      credentials: RefreshRepositoryFake(
        session: try StoredOAuthSession(
          serverURL: bearerContext.baseURL,
          credentials: StoredOAuthCredentials(
            accessToken: "access-only",
            refreshToken: nil
          ),
          isVerified: true
        )
      ),
      tokenRefresher: refresher
    )
    #expect(
      try await bearerCoordinator.recoverUnauthorizedRequest(for: bearerContext) == nil
    )
    #expect(await refresher.callCount == 0)
  }

  @Test("A credential transition prevents a completed refresh from being retried")
  func transitionInvalidatesRefreshResult() async throws {
    let context = try SureRequestContext(
      baseURL: #require(URL(string: "https://sure.example")),
      authorization: .bearer("expired-access")
    )
    let repository = RefreshRepositoryFake(
      session: try StoredOAuthSession(
        serverURL: context.baseURL,
        credentials: StoredOAuthCredentials(
          accessToken: "expired-access",
          refreshToken: "refresh-token"
        ),
        isVerified: true
      )
    )
    let refresher = SuspendedOAuthTokenRefresher()
    let coordinator = OAuthRefreshCoordinator(
      session: SureSession(context: context),
      credentials: repository,
      tokenRefresher: refresher
    )
    let recovery = Task {
      try await coordinator.recoverUnauthorizedRequest(for: context)
    }
    await refresher.waitUntilStarted()
    let transition = Task { await coordinator.beginCredentialChange() }
    await Task.yield()

    await refresher.complete(with: PasskeyOAuthTokens(
      accessToken: "rotated-access",
      refreshToken: "rotated-refresh"
    ))

    #expect(try await recovery.value == nil)
    await transition.value
    await coordinator.endCredentialChange()
  }
}

private final class RefreshRepositoryFake: CredentialRepository, @unchecked Sendable {
  private let lock = NSLock()
  private var storedSession: StoredOAuthSession?

  var credentials: StoredOAuthCredentials? {
    lock.withLock { storedSession?.credentials }
  }

  init(session: StoredOAuthSession?) {
    storedSession = session
  }

  func loadCredentials() throws -> StoredCredentialSnapshot {
    lock.withLock {
      StoredCredentialSnapshot(session: storedSession.map(StoredAuthenticatedSession.oauth))
    }
  }

  func replaceSession(_ session: StoredAuthenticatedSession?) throws {
    lock.withLock { storedSession = StoredCredentialSnapshot(session: session).oauthSession }
  }
}

private actor SuspendedOAuthTokenRefresher: OAuthTokenRefreshing {
  private(set) var callCount = 0
  private var continuation: CheckedContinuation<PasskeyOAuthTokens, Error>?

  func refresh(
    refreshToken: String,
    serverURL: String,
    source: OAuthTokenSource
  ) async throws -> PasskeyOAuthTokens {
    callCount += 1
    return try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
    }
  }

  func waitUntilStarted() async {
    while callCount == 0 {
      await Task.yield()
    }
  }

  func complete(with tokens: PasskeyOAuthTokens) {
    continuation?.resume(returning: tokens)
    continuation = nil
  }
}
