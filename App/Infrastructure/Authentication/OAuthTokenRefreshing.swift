protocol OAuthTokenRefreshing: Sendable {
  func refresh(
    refreshToken: String,
    serverURL: String
  ) async throws -> PasskeyOAuthTokens
}

extension OAuthHTTPClient: OAuthTokenRefreshing {
  func refresh(
    refreshToken: String,
    serverURL: String
  ) async throws -> PasskeyOAuthTokens {
    try await refresh(
      refreshToken: refreshToken,
      server: OAuthServerURL(serverURL)
    )
  }
}
