import CryptoKit
import Foundation

enum ConnectionCacheIdentity {
  // Preserve the namespace of existing installations when upgrading their
  // credential envelope. New logins supply an independently generated ID.
  static func legacyOAuth(_ credentials: StoredOAuthCredentials, source: OAuthTokenSource) -> String {
    let sourceName: String
    switch source {
    case .dynamicClient: sourceName = "dynamic-client"
    case .mobileDevice(let id): sourceName = "mobile-device:\(id)"
    }
    return digest("oauth:\(sourceName):\(credentials.accessToken)")
  }

  static func legacyAPIKey(_ key: String) -> String { digest("api-key:\(key)") }

  private static func digest(_ value: String) -> String {
    Data(SHA256.hash(data: Data(value.utf8))).base64EncodedString()
  }
}
