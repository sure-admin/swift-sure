import Foundation

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
