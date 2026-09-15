import Foundation

@MainActor
protocol ConnectionAuthenticating: AnyObject {
  var status: ConnectionStatus { get }
  var pendingOnboarding: MobileSSOOnboardingContext? { get }
  var isConfigured: Bool { get }
  var isSignedOut: Bool { get }
  var generation: Int { get }
  var canLogOut: Bool { get }
  var allowsWalletPreview: Bool { get }
  var connectionID: String? { get }
  var serverURL: URL? { get }
  var isOAuthConnected: Bool { get }
  func matchesStoredAPIKey(_ key: String) -> Bool
  func signIn(_ method: AuthenticationMethod, serverURL: String) async
  func cancel()
  func cancelOnboarding()
  func logOut() async
}

enum AuthenticationMethod {
  case apiKey(String), passkey, password(email: String, password: String), provider(SSOProvider)
}
