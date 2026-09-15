import Foundation
import Observation

/// Connection-screen drafts and intents; committed identity belongs to the session.
@MainActor
@Observable
final class SureConnection {
  var serverURL: String
  var apiKey: String
  var email = ""
  var password = ""
  let authentication: any ConnectionAuthenticating

  init(initialState: SureConnectionInitialState, authentication: any ConnectionAuthenticating) {
    self.authentication = authentication
    serverURL = initialState.serverURL
    apiKey = initialState.isExplicitlySignedOut ? "" : initialState.credentials.apiKey ?? ""
  }

  var status: ConnectionStatus { authentication.status }
  var isConfigured: Bool { authentication.isConfigured }
  var isSignedOut: Bool { authentication.isSignedOut }
  var sessionGeneration: Int { authentication.generation }
  var pendingSSOOnboarding: MobileSSOOnboardingContext? { authentication.pendingOnboarding }
  var canLogOut: Bool { authentication.canLogOut }
  var allowsWalletPreview: Bool { authentication.allowsWalletPreview }
  var connectedSnapshotIdentity: String? { authentication.connectionID }
  var connectedServerURL: URL? { authentication.serverURL }
  var isOAuthConnected: Bool { authentication.isOAuthConnected }
  var isAPIKeyStored: Bool {
    !normalizedAPIKey.isEmpty && authentication.matchesStoredAPIKey(normalizedAPIKey)
  }
  var canConnectWithAPIKey: Bool { !normalizedAPIKey.isEmpty && canSignInWithPasskey }
  var canSignInWithPasskey: Bool {
    (try? OAuthServerURL(serverURL.trimmingCharacters(in: .whitespacesAndNewlines))) != nil
  }
  var canSignInWithPassword: Bool {
    !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty && canSignInWithPasskey
  }

  func signInWithPasskey() async { await signIn(.passkey) }
  func signInWithPassword() async {
    await signIn(.password(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password))
  }
  func signIn(with provider: SSOProvider) async { await signIn(.provider(provider)) }
  func connectWithAPIKey() async { await signIn(.apiKey(normalizedAPIKey)) }
  func cancelAuthentication() { authentication.cancel() }
  func cancelSSOOnboarding() { authentication.cancelOnboarding() }

  func suspendAuthentication() {
    authentication.cancel()
    apiKey = ""
    email = ""
    password = ""
    authentication.cancelOnboarding()
  }

  func logOut() async {
    apiKey = ""
    email = ""
    password = ""
    await authentication.logOut()
  }

  private func signIn(_ method: AuthenticationMethod) async {
    await authentication.signIn(method, serverURL: serverURL)
    if status == .connected {
      serverURL = connectedServerURL?.absoluteString ?? serverURL
      if case .apiKey(let key) = method { apiKey = key } else { apiKey = "" }
      password = ""
    }
  }

  private var normalizedAPIKey: String { apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension SureConnection: ConnectionStateProviding { }
