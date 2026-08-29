import Foundation

protocol OAuthClientIDStoring: Sendable {
  func clientID(for serverURL: URL) -> String?
  func setClientID(_ clientID: String, for serverURL: URL)
}

struct UserDefaultsOAuthClientIDStore: OAuthClientIDStoring, @unchecked Sendable {
  var userDefaults: UserDefaults

  init(userDefaults: UserDefaults = .standard) {
    self.userDefaults = userDefaults
  }

  func clientID(for serverURL: URL) -> String? {
    userDefaults.string(forKey: cacheKey(for: serverURL))
  }

  func setClientID(_ clientID: String, for serverURL: URL) {
    userDefaults.set(clientID, forKey: cacheKey(for: serverURL))
  }

  private func cacheKey(for serverURL: URL) -> String {
    "sureOAuthClientID.\(serverURL.absoluteString)"
  }
}
