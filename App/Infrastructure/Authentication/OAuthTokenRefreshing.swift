protocol OAuthTokenRefreshing: Sendable {
  func refresh(
    refreshToken: String,
    serverURL: String,
    source: OAuthTokenSource
  ) async throws -> PasskeyOAuthTokens
}

struct OAuthTokenRefreshService: OAuthTokenRefreshing {
  var oauthClient: OAuthHTTPClient
  var mobileClient: MobileSSOHTTPClient

  func refresh(
    refreshToken: String,
    serverURL: String,
    source: OAuthTokenSource
  ) async throws -> PasskeyOAuthTokens {
    let server = try OAuthServerURL(serverURL)
    switch source {
    case .dynamicClient:
      return try await oauthClient.refresh(
        refreshToken: refreshToken,
        server: server
      )
    case .mobileDevice(let deviceID):
      return try await mobileClient.refresh(
        refreshToken: refreshToken,
        deviceID: deviceID,
        server: server
      )
    }
  }
}
