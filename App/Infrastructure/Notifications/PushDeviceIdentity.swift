import CryptoKit
import Foundation
import Security

/// A different secret per server prevents one self-hosted instance from claiming
/// an installation's registration on another. It intentionally survives logout.
struct PushDeviceIdentity {
  var secrets: any SecretValueStoring
  var makeSecret: () throws -> String = {
    var bytes = [UInt8](repeating: 0, count: 32)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
      throw DataFailure.persistence
    }
    return bytes.map { String(format: "%02x", $0) }.joined()
  }

  func key(for server: URL) throws -> String {
    let normalized = try SureRequestContext(baseURL: server, authorization: nil).baseURL
    let digest = SHA256.hash(data: Data(normalized.absoluteString.utf8))
      .map { String(format: "%02x", $0) }.joined()
    let account = "sure.push-device." + digest
    if let value = secrets.value(for: account, scope: .deviceOnly) { return value }
    let secret = try makeSecret()
    try secrets.setValue(secret, for: account, scope: .deviceOnly)
    return secret
  }
}
