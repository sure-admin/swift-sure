import Foundation

protocol ConnectionPreferences: Sendable {
  func serverURL() -> String?
  func setServerURL(_ serverURL: String)
  func isExplicitlySignedOut() -> Bool
  func setExplicitlySignedOut(_ isSignedOut: Bool)
  func hasConnectedToSure() -> Bool
  func setHasConnectedToSure(_ connected: Bool)
}

struct UserDefaultsConnectionPreferences: ConnectionPreferences, @unchecked Sendable {
  var defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func serverURL() -> String? {
    defaults.string(forKey: StorageKey.serverURL)
  }

  func setServerURL(_ serverURL: String) {
    defaults.set(serverURL, forKey: StorageKey.serverURL)
  }

  func isExplicitlySignedOut() -> Bool {
    defaults.bool(forKey: StorageKey.isExplicitlySignedOut)
  }

  func setExplicitlySignedOut(_ isSignedOut: Bool) {
    defaults.set(isSignedOut, forKey: StorageKey.isExplicitlySignedOut)
  }

  func hasConnectedToSure() -> Bool { defaults.bool(forKey: "sureHasConnected") }
  func setHasConnectedToSure(_ connected: Bool) { defaults.set(connected, forKey: "sureHasConnected") }

  func requiresWalletReconnect() -> Bool {
    defaults.bool(forKey: "sureRequiresWalletReconnect")
  }

  func setRequiresWalletReconnect(_ required: Bool) {
    defaults.set(required, forKey: "sureRequiresWalletReconnect")
  }

  private enum StorageKey {
    static let serverURL = "sureServerURL"
    static let isExplicitlySignedOut = "sureExplicitlySignedOut"
  }
}
