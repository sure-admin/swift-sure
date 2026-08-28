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
  private(set) var accessToken: String
  private(set) var isAPIKeyStored = false
  private(set) var hasVerifiedAPIKey = false
  private(set) var isSignedOut = false
  var status: ConnectionStatus = .notConnected

  var isConfigured: Bool {
    !isSignedOut && hasUsableCredential
  }

  var isPasskeyConnected: Bool {
    !accessToken.isEmpty
  }

  var canConnectWithAPIKey: Bool {
    URL(string: serverURL) != nil && !apiKey.isEmpty
  }

  var canLogOut: Bool {
    !isSignedOut && hasUsableCredential
  }

  private var hasUsableCredential: Bool {
    URL(string: serverURL) != nil && (!accessToken.isEmpty || !apiKey.isEmpty)
  }

  private init() {
    let savedAPIKey = KeychainStore.read(account: "apiKey", scope: .iCloud) ?? ""
    serverURL = UserDefaults.standard.string(forKey: "sureServerURL") ?? "https://demo.sure.am"
    apiKey = savedAPIKey
    accessToken = KeychainStore.read(account: "oauthAccessToken") ?? ""
    isSignedOut = UserDefaults.standard.bool(forKey: "sureExplicitlySignedOut")
    isAPIKeyStored = KeychainStore.contains(account: "apiKey", scope: .iCloud)
    hasVerifiedAPIKey = !savedAPIKey.isEmpty
      && KeychainStore.read(account: "verifiedAPIKey", scope: .iCloud) == "true"
  }

  func test() async {
    guard hasUsableCredential else {
      status = .failed("Sign in with a passkey or enter an API key first.")
      return
    }
    status = .connecting
    do {
      _ = try await SureAPIClient(connection: self).request(path: "/api/v1/accounts", method: "GET")
      markSignedIn()
      status = .connected
      setAPIKeyVerified(true)
      #if os(iOS)
      await NotificationManager.shared.registerStoredDeviceTokenIfNeeded()
      #endif
    } catch {
      status = .failed(error.localizedDescription)
    }
  }

  @MainActor
  func signInWithPasskey() async {
    let previousAccessToken = accessToken
    status = .connecting
    do {
      let tokens = try await PasskeyOAuthService().signIn(serverURL: serverURL)
      accessToken = tokens.accessToken
      try await verifyCurrentCredentials()
      guard KeychainStore.save(tokens.accessToken, account: "oauthAccessToken") else {
        throw PasskeyOAuthError.backend("The access token couldn’t be saved in Keychain.")
      }
      if let refreshToken = tokens.refreshToken {
        KeychainStore.save(refreshToken, account: "oauthRefreshToken")
      }
      markSignedIn()
      status = .connected
      #if os(iOS)
      await NotificationManager.shared.registerStoredDeviceTokenIfNeeded()
      #endif
    } catch {
      accessToken = previousAccessToken
      KeychainStore.save(previousAccessToken, account: "oauthAccessToken")
      status = .failed(error.localizedDescription)
    }
  }

  @MainActor
  func connectWithAPIKey() async {
    let previousAccessToken = accessToken
    let wasSignedOut = isSignedOut
    accessToken = ""
    await test()
    if status == .connected {
      KeychainStore.save("", account: "oauthAccessToken")
      KeychainStore.save("", account: "oauthRefreshToken")
    } else {
      accessToken = previousAccessToken
      isSignedOut = wasSignedOut
    }
  }

  @MainActor
  func logOut() async {
    #if os(iOS)
    await NotificationManager.shared.disableInsightNotifications()
    #endif
    let oauthService = PasskeyOAuthService()
    await oauthService.revoke(token: accessToken, serverURL: serverURL)
    if let refreshToken = KeychainStore.read(account: "oauthRefreshToken") {
      await oauthService.revoke(token: refreshToken, serverURL: serverURL)
    }
    accessToken = ""
    KeychainStore.save("", account: "oauthAccessToken")
    KeychainStore.save("", account: "oauthRefreshToken")
    isSignedOut = true
    UserDefaults.standard.set(true, forKey: "sureExplicitlySignedOut")
    UserDefaults.standard.set(false, forKey: "insightNotificationsEnabled")
    status = .notConnected
    FinanceDataStore.shared.disconnect()
  }

  private func verifyCurrentCredentials() async throws {
    _ = try await SureAPIClient(connection: self).request(path: "/api/v1/accounts", method: "GET")
  }

  private func setAPIKeyVerified(_ isVerified: Bool) {
    hasVerifiedAPIKey = isVerified
    KeychainStore.save(
      isVerified ? "true" : "",
      account: "verifiedAPIKey",
      scope: .iCloud
    )
  }

  private func markSignedIn() {
    isSignedOut = false
    UserDefaults.standard.set(false, forKey: "sureExplicitlySignedOut")
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
