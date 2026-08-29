struct StoredCredentialSnapshot: Equatable, Sendable {
  var session: StoredAuthenticatedSession?

  var oauthSession: StoredOAuthSession? {
    guard case .oauth(let session) = session else { return nil }
    return session
  }

  var apiKeySession: StoredAPIKeySession? {
    guard case .apiKey(let session) = session else { return nil }
    return session
  }

  var oauthCredentials: StoredOAuthCredentials? {
    oauthSession?.credentials
  }

  var apiKey: String? {
    apiKeySession?.apiKey
  }

  var isAPIKeyVerified: Bool {
    apiKeySession?.isVerified ?? false
  }
}
