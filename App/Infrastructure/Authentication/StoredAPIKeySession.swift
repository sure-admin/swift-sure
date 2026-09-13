import Foundation

struct StoredAPIKeySession: Codable, Equatable, Sendable {
  var serverURL: URL
  var apiKey: String
  var isVerified: Bool
  var connectionID: String

  init(serverURL: URL, apiKey: String, isVerified: Bool, connectionID: String? = nil) throws {
    let context = try SureRequestContext(
      baseURL: serverURL,
      authorization: .apiKey(apiKey)
    )
    self.serverURL = context.baseURL
    self.apiKey = apiKey
    self.isVerified = isVerified
    self.connectionID = connectionID ?? ConnectionCacheIdentity.legacyAPIKey(apiKey)
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      serverURL: container.decode(URL.self, forKey: .serverURL),
      apiKey: container.decode(String.self, forKey: .apiKey),
      isVerified: container.decode(Bool.self, forKey: .isVerified),
      connectionID: container.decodeIfPresent(String.self, forKey: .connectionID)
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
    case connectionID
  }
}
