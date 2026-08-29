import Foundation

struct StoredOAuthCredentials: Codable, Equatable, Sendable {
  let accessToken: String
  let refreshToken: String?

  init(accessToken: String, refreshToken: String?) throws {
    guard !accessToken.isEmpty else {
      throw StoredOAuthCredentialsError.invalidAccessToken
    }
    self.accessToken = accessToken
    self.refreshToken = refreshToken.flatMap { $0.isEmpty ? nil : $0 }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      accessToken: container.decode(String.self, forKey: .accessToken),
      refreshToken: container.decodeIfPresent(String.self, forKey: .refreshToken)
    )
  }
}

private enum StoredOAuthCredentialsError: LocalizedError {
  case invalidAccessToken

  var errorDescription: String? {
    "The stored OAuth credentials are invalid."
  }
}
