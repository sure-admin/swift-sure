import Foundation

struct PasskeyOAuthTokens: Decodable, Equatable, Sendable {
  var accessToken: String
  var refreshToken: String?
  var tokenType: String?
  var expiresIn: Int?
  var createdAt: Int?

  init(
    accessToken: String,
    refreshToken: String?,
    tokenType: String? = nil,
    expiresIn: Int? = nil,
    createdAt: Int? = nil
  ) {
    self.accessToken = accessToken
    self.refreshToken = refreshToken
    self.tokenType = tokenType
    self.expiresIn = expiresIn
    self.createdAt = createdAt
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    accessToken = try container.decode(String.self, forKey: .accessToken)
    guard !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw DecodingError.dataCorruptedError(
        forKey: .accessToken,
        in: container,
        debugDescription: "Expected a nonempty access token."
      )
    }
    refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
    if refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
      refreshToken = nil
    }
    tokenType = try container.decodeIfPresent(String.self, forKey: .tokenType)
    expiresIn = try Self.decodeIntegerIfPresent(from: container, forKey: .expiresIn)
    createdAt = try Self.decodeIntegerIfPresent(from: container, forKey: .createdAt)
  }

  enum CodingKeys: String, CodingKey {
    case accessToken = "access_token"
    case refreshToken = "refresh_token"
    case tokenType = "token_type"
    case expiresIn = "expires_in"
    case createdAt = "created_at"
  }

  private static func decodeIntegerIfPresent(
    from container: KeyedDecodingContainer<CodingKeys>,
    forKey key: CodingKeys
  ) throws -> Int? {
    guard container.contains(key) else {
      return nil
    }
    if try container.decodeNil(forKey: key) {
      return nil
    }
    if let value = try? container.decode(Int.self, forKey: key) {
      return value
    }
    let string = try container.decode(String.self, forKey: key)
    guard let value = Int(string) else {
      throw DecodingError.dataCorruptedError(
        forKey: key,
        in: container,
        debugDescription: "Expected an integer or integer string."
      )
    }
    return value
  }
}
