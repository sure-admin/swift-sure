import Foundation
import Observation

/// Connection-screen drafts and intents; committed identity belongs to the session.
@MainActor
@Observable
final class SureConnection {
  var serverURL: String {
    didSet { if oldValue != serverURL { resetSecondFactor() } }
  }
  var apiKey: String
  var email = "" {
    didSet { if oldValue != email { resetSecondFactor() } }
  }
  var password = "" {
    didSet { if oldValue != password { resetSecondFactor() } }
  }
  var secondFactorCode = "" {
    didSet { if !secondFactorCode.isEmpty { secondFactorRejected = false } }
  }
  private(set) var requiresSecondFactor = false
  private(set) var secondFactorRejected = false
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
  var serverWebsiteURL: URL? {
    try? OAuthServerURL(serverURL.trimmingCharacters(in: .whitespacesAndNewlines)).url
  }
  var serverDisplayName: String {
    guard let host = serverWebsiteURL?.host, !host.isEmpty else { return "Sure" }
    return host
  }
  var isDemoServer: Bool {
    SureDemoServer.matchesBaseURL(try? OAuthServerURL(serverURL.trimmingCharacters(in: .whitespacesAndNewlines)).url)
  }
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
      && (!requiresSecondFactor || !secondFactorCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
  }

  func signInWithPasskey() async { await signIn(.passkey) }
  func prepareDemoSignIn() {
    resetSecondFactor()
    authentication.cancelOnboarding()
    serverURL = SureDemoServer.baseURL.absoluteString
    apiKey = ""
    email = SureDemoServer.email
    password = SureDemoServer.password
  }

  func signInWithPassword() async {
    let submittedServer = serverURL
    let submittedEmail = email
    let submittedPassword = password
    let code = requiresSecondFactor ? secondFactorCode.trimmingCharacters(in: .whitespacesAndNewlines) : nil
    await signIn(.password(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password, otpCode: code))
    if status == .requiresSecondFactor,
       serverURL == submittedServer, email == submittedEmail, password == submittedPassword {
      requiresSecondFactor = true
      secondFactorRejected = code != nil
      secondFactorCode = ""
    }
  }
  func signIn(with provider: SSOProvider) async { await signIn(.provider(provider)) }
  func connectWithAPIKey() async { await signIn(.apiKey(normalizedAPIKey)) }
  func cancelAuthentication() {
    authentication.cancel()
    secondFactorCode = ""
    secondFactorRejected = false
  }
  func cancelSecondFactor() {
    authentication.cancel()
    resetSecondFactor()
    password = ""
  }

  private func resetSecondFactor() {
    requiresSecondFactor = false
    secondFactorRejected = false
    secondFactorCode = ""
  }

  func cancelSSOOnboarding() { authentication.cancelOnboarding() }

  func suspendAuthentication() {
    resetSecondFactor()
    authentication.cancel()
    apiKey = ""
    email = ""
    password = ""
    authentication.cancelOnboarding()
  }

  func logOut() async {
    resetSecondFactor()
    apiKey = ""
    email = ""
    password = ""
    await authentication.logOut()
    serverURL = ""
  }

  private func signIn(_ method: AuthenticationMethod) async {
    switch method {
    case .password: break
    default: resetSecondFactor()
    }
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
