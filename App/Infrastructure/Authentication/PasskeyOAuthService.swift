import AuthenticationServices
import CryptoKit
import Foundation
import Security

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
final class PasskeyOAuthService: NSObject, ASWebAuthenticationPresentationContextProviding {
  private static let callbackPort: UInt16 = 53_921
  private static let callbackPath = "/oauth/callback"

  private var authenticationSession: ASWebAuthenticationSession?
  private var accessGate: BackendAccessGate
  private var oauthClient: OAuthHTTPClient

  init(oauthClient: OAuthHTTPClient, accessGate: BackendAccessGate = BackendAccessGate()) {
    self.accessGate = accessGate
    self.oauthClient = oauthClient
    super.init()
  }

  func cancelAuthentication() { authenticationSession?.cancel() }

  func signIn(serverURL: String) async throws -> PasskeyOAuthTokens {
    try accessGate.check()
    let server = try OAuthServerURL(serverURL)
    let loopbackServer = try OAuthLoopbackServer(
      port: Self.callbackPort,
      path: Self.callbackPath
    )
    try await loopbackServer.start()
    defer {
      loopbackServer.cancel(with: CancellationError())
      authenticationSession?.cancel()
      authenticationSession = nil
    }

    let clientID = try await oauthClient.clientID(
      server: server,
      redirectURL: loopbackServer.redirectURL
    )
    let verifier = try randomURLSafeString(byteCount: 32)
    let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    let state = try randomURLSafeString(byteCount: 24)
    let authorizationURL = try OAuthAuthorizationURL.make(
      server: server,
      clientID: clientID,
      redirectURL: loopbackServer.redirectURL,
      challenge: challenge,
      state: state
    )

    try accessGate.check()
    let session = ASWebAuthenticationSession(
      url: authorizationURL,
      callbackURLScheme: nil
    ) { [weak loopbackServer] _, error in
      if let error {
        if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
          loopbackServer?.cancel(with: CancellationError())
        } else {
          loopbackServer?.cancel(with: error)
        }
      }
    }
    session.presentationContextProvider = self
    session.prefersEphemeralWebBrowserSession = false
    authenticationSession = session
    guard session.start() else {
      throw PasskeyOAuthError.couldNotStart
    }

    let callbackURL = try await withTaskCancellationHandler {
      try await loopbackServer.waitForCallback()
    } onCancel: {
      loopbackServer.cancel(with: CancellationError())
    }
    let callback = try OAuthAuthorizationCallback.parse(
      callbackURL,
      expectedState: state
    )
    return try await oauthClient.exchangeAuthorizationCode(
      callback.code,
      verifier: verifier,
      clientID: clientID,
      redirectURL: loopbackServer.redirectURL,
      server: server
    )
  }

  func revoke(token: String, serverURL: String) async {
    guard !token.isEmpty,
          let server = try? OAuthServerURL(serverURL) else {
      return
    }
    try? await oauthClient.revoke(token: token, server: server)
  }

  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    #if os(iOS)
    return UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    #elseif os(macOS)
    return NSApplication.shared.keyWindow
      ?? NSApplication.shared.windows.first
      ?? ASPresentationAnchor()
    #endif
  }

  private func randomURLSafeString(byteCount: Int) throws -> String {
    var bytes = [UInt8](repeating: 0, count: byteCount)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
      throw PasskeyOAuthError.randomGenerationFailed
    }
    return Data(bytes).base64URLEncodedString()
  }
}

extension PasskeyOAuthService: OAuthAuthenticating { }

private extension Data {
  func base64URLEncodedString() -> String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
