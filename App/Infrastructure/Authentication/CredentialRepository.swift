import Foundation

protocol CredentialRepository: Sendable {
  func loadCredentials() throws -> StoredCredentialSnapshot
  func replaceSession(_ session: StoredAuthenticatedSession?) throws
}

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

enum StoredAuthenticatedSession: Codable, Equatable, Sendable {
  case oauth(StoredOAuthSession)
  case apiKey(StoredAPIKeySession)

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(Kind.self, forKey: .kind) {
    case .oauth:
      self = .oauth(try container.decode(StoredOAuthSession.self, forKey: .oauth))
    case .apiKey:
      self = .apiKey(try container.decode(StoredAPIKeySession.self, forKey: .apiKey))
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .oauth(let session):
      try container.encode(Kind.oauth, forKey: .kind)
      try container.encode(session, forKey: .oauth)
    case .apiKey(let session):
      try container.encode(Kind.apiKey, forKey: .kind)
      try container.encode(session, forKey: .apiKey)
    }
  }

  private enum CodingKeys: CodingKey {
    case kind
    case oauth
    case apiKey
  }

  private enum Kind: String, Codable {
    case oauth
    case apiKey
  }
}

struct StoredOAuthSession: Codable, Equatable, Sendable {
  var serverURL: URL
  var credentials: StoredOAuthCredentials
  var isVerified: Bool

  init(
    serverURL: URL,
    credentials: StoredOAuthCredentials,
    isVerified: Bool
  ) throws {
    let context = try SureRequestContext(
      baseURL: serverURL,
      authorization: .bearer(credentials.accessToken)
    )
    self.serverURL = context.baseURL
    self.credentials = credentials
    self.isVerified = isVerified
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      serverURL: container.decode(URL.self, forKey: .serverURL),
      credentials: container.decode(StoredOAuthCredentials.self, forKey: .credentials),
      isVerified: try container.decodeIfPresent(Bool.self, forKey: .isVerified) ?? false
    )
  }

  func requestContext() throws -> SureRequestContext {
    try SureRequestContext(
      baseURL: serverURL,
      authorization: .bearer(credentials.accessToken)
    )
  }

  private enum CodingKeys: CodingKey {
    case serverURL
    case credentials
    case isVerified
  }
}

struct StoredAPIKeySession: Codable, Equatable, Sendable {
  var serverURL: URL
  var apiKey: String
  var isVerified: Bool

  init(serverURL: URL, apiKey: String, isVerified: Bool) throws {
    let context = try SureRequestContext(
      baseURL: serverURL,
      authorization: .apiKey(apiKey)
    )
    self.serverURL = context.baseURL
    self.apiKey = apiKey
    self.isVerified = isVerified
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      serverURL: container.decode(URL.self, forKey: .serverURL),
      apiKey: container.decode(String.self, forKey: .apiKey),
      isVerified: container.decode(Bool.self, forKey: .isVerified)
    )
  }

  func requestContext() throws -> SureRequestContext {
    try SureRequestContext(
      baseURL: serverURL,
      authorization: .apiKey(apiKey)
    )
  }

  private enum CodingKeys: CodingKey {
    case serverURL
    case apiKey
    case isVerified
  }
}

enum CredentialRepositoryError: LocalizedError, Equatable {
  case invalidStoredCredentials
  case persistenceFailed

  var errorDescription: String? {
    switch self {
    case .invalidStoredCredentials:
      "The saved Sure credentials are invalid. Sign in again."
    case .persistenceFailed:
      "The Sure credentials couldn’t be saved securely."
    }
  }
}
