import Foundation

@MainActor
protocol OAuthAuthenticating {
  func signIn(serverURL: String) async throws -> PasskeyOAuthTokens
  func revoke(token: String, serverURL: String) async
}
