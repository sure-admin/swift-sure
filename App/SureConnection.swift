import Foundation
import Observation

@Observable
final class SureConnection {
  static let shared = SureConnection()

  var serverURL: String {
    didSet { UserDefaults.standard.set(serverURL, forKey: "sureServerURL") }
  }
  var apiKey: String {
    didSet {
      isAPIKeyStored = KeychainStore.save(apiKey, account: "apiKey", scope: .iCloud)
      if apiKey != oldValue {
        setAPIKeyVerified(false)
      }
    }
  }
  private(set) var isAPIKeyStored = false
  private(set) var hasVerifiedAPIKey = false
  var status: ConnectionStatus = .notConnected

  var isConfigured: Bool {
    URL(string: serverURL) != nil && !apiKey.isEmpty
  }

  private init() {
    let savedAPIKey = KeychainStore.read(account: "apiKey", scope: .iCloud) ?? ""
    serverURL = UserDefaults.standard.string(forKey: "sureServerURL") ?? "https://demo.sure.am"
    apiKey = savedAPIKey
    isAPIKeyStored = KeychainStore.contains(account: "apiKey", scope: .iCloud)
    hasVerifiedAPIKey = !savedAPIKey.isEmpty
      && KeychainStore.read(account: "verifiedAPIKey", scope: .iCloud) == "true"
  }

  func test() async {
    guard isConfigured else {
      status = .failed("Enter an API key first.")
      return
    }
    status = .connecting
    do {
      _ = try await SureAPIClient(connection: self).request(path: "/api/v1/accounts", method: "GET")
      status = .connected
      setAPIKeyVerified(true)
    } catch {
      status = .failed(error.localizedDescription)
    }
  }

  private func setAPIKeyVerified(_ isVerified: Bool) {
    hasVerifiedAPIKey = isVerified
    KeychainStore.save(
      isVerified ? "true" : "",
      account: "verifiedAPIKey",
      scope: .iCloud
    )
  }
}

enum ConnectionStatus: Equatable {
  case notConnected
  case connecting
  case connected
  case failed(String)

  var label: String {
    switch self {
    case .notConnected: "Not connected"
    case .connecting: "Connecting…"
    case .connected: "Connected"
    case .failed: "Connection failed"
    }
  }
}
