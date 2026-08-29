import Foundation

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
