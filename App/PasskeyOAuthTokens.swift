import Foundation

struct PasskeyOAuthTokens: Decodable {
  var accessToken: String
  var refreshToken: String?

  enum CodingKeys: String, CodingKey {
    case accessToken = "access_token"
    case refreshToken = "refresh_token"
  }
}
