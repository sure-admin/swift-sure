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

  func signIn(serverURL: String) async throws -> PasskeyOAuthTokens {
    guard let baseURL = normalizedBaseURL(serverURL) else {
      throw PasskeyOAuthError.invalidServerURL
    }

    let loopbackServer = try OAuthLoopbackServer(
      port: Self.callbackPort,
      path: Self.callbackPath
    )
    try await loopbackServer.start()

    let clientID = try await clientID(baseURL: baseURL, redirectURL: loopbackServer.redirectURL)
    let verifier = try randomURLSafeString(byteCount: 32)
    let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    let state = try randomURLSafeString(byteCount: 24)
    let authorizationURL = try makeAuthorizationURL(
      baseURL: baseURL,
      clientID: clientID,
      redirectURL: loopbackServer.redirectURL,
      challenge: challenge,
      state: state
    )

    let session = ASWebAuthenticationSession(
      url: authorizationURL,
      callbackURLScheme: nil
    ) { [weak loopbackServer] _, error in
      if let error {
        loopbackServer?.cancel(with: error)
      }
    }
    session.presentationContextProvider = self
    session.prefersEphemeralWebBrowserSession = false
    authenticationSession = session
    guard session.start() else {
      throw PasskeyOAuthError.couldNotStart
    }

    defer {
      authenticationSession?.cancel()
      authenticationSession = nil
    }

    let callbackURL = try await loopbackServer.waitForCallback()
    let callback = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
    let values = Dictionary(uniqueKeysWithValues: (callback?.queryItems ?? []).compactMap { item in
      item.value.map { (item.name, $0) }
    })
    if let message = values["error_description"] ?? values["error"] {
      throw PasskeyOAuthError.backend(message)
    }
    guard values["state"] == state, let code = values["code"] else {
      throw PasskeyOAuthError.invalidResponse
    }

    return try await exchangeCode(
      code,
      verifier: verifier,
      clientID: clientID,
      redirectURL: loopbackServer.redirectURL,
      baseURL: baseURL
    )
  }

  func revoke(token: String, serverURL: String) async {
    guard !token.isEmpty,
          let baseURL = normalizedBaseURL(serverURL),
          let clientID = UserDefaults.standard.string(forKey: clientIDCacheKey(baseURL: baseURL)) else { return }
    let url = baseURL.appending(path: "oauth/revoke")
    var components = URLComponents()
    components.queryItems = [
      URLQueryItem(name: "token", value: token),
      URLQueryItem(name: "client_id", value: clientID)
    ]
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
    _ = try? await URLSession.shared.data(for: request)
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

  private func clientID(baseURL: URL, redirectURL: URL) async throws -> String {
    let cacheKey = clientIDCacheKey(baseURL: baseURL)
    if let saved = UserDefaults.standard.string(forKey: cacheKey) {
      return saved
    }

    let url = baseURL.appending(path: "register")
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.httpBody = try JSONEncoder().encode(RegistrationRequest(
      clientName: "Sure for Apple",
      redirectURIs: [redirectURL.absoluteString]
    ))
    let (data, response) = try await URLSession.shared.data(for: request)
    try validate(response: response, data: data)
    let registration = try JSONDecoder().decode(RegistrationResponse.self, from: data)
    UserDefaults.standard.set(registration.clientID, forKey: cacheKey)
    return registration.clientID
  }

  private func clientIDCacheKey(baseURL: URL) -> String {
    "sureOAuthClientID.\(baseURL.absoluteString)"
  }

  private func exchangeCode(
    _ code: String,
    verifier: String,
    clientID: String,
    redirectURL: URL,
    baseURL: URL
  ) async throws -> PasskeyOAuthTokens {
    let url = baseURL.appending(path: "oauth/token")
    var components = URLComponents()
    components.queryItems = [
      URLQueryItem(name: "grant_type", value: "authorization_code"),
      URLQueryItem(name: "code", value: code),
      URLQueryItem(name: "client_id", value: clientID),
      URLQueryItem(name: "redirect_uri", value: redirectURL.absoluteString),
      URLQueryItem(name: "code_verifier", value: verifier)
    ]
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
    let (data, response) = try await URLSession.shared.data(for: request)
    try validate(response: response, data: data)
    return try JSONDecoder().decode(PasskeyOAuthTokens.self, from: data)
  }

  private func makeAuthorizationURL(
    baseURL: URL,
    clientID: String,
    redirectURL: URL,
    challenge: String,
    state: String
  ) throws -> URL {
    var components = URLComponents(
      url: baseURL.appending(path: "oauth/authorize"),
      resolvingAgainstBaseURL: false
    )
    components?.queryItems = [
      URLQueryItem(name: "client_id", value: clientID),
      URLQueryItem(name: "redirect_uri", value: redirectURL.absoluteString),
      URLQueryItem(name: "response_type", value: "code"),
      URLQueryItem(name: "scope", value: "read_write"),
      URLQueryItem(name: "code_challenge", value: challenge),
      URLQueryItem(name: "code_challenge_method", value: "S256"),
      URLQueryItem(name: "state", value: state)
    ]
    guard let url = components?.url else { throw PasskeyOAuthError.invalidServerURL }
    return url
  }

  private func normalizedBaseURL(_ string: String) -> URL? {
    guard let url = URL(string: string), url.scheme == "https", url.host != nil else { return nil }
    return url
  }

  private func randomURLSafeString(byteCount: Int) throws -> String {
    var bytes = [UInt8](repeating: 0, count: byteCount)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
      throw PasskeyOAuthError.randomGenerationFailed
    }
    return Data(bytes).base64URLEncodedString()
  }

  private func validate(response: URLResponse, data: Data) throws {
    guard let response = response as? HTTPURLResponse else {
      throw PasskeyOAuthError.invalidResponse
    }
    guard 200..<300 ~= response.statusCode else {
      let payload = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data)
      throw PasskeyOAuthError.backend(
        payload?.errorDescription ?? payload?.error ?? "Sure returned HTTP \(response.statusCode)."
      )
    }
  }
}

private struct RegistrationRequest: Encodable {
  var clientName: String
  var redirectURIs: [String]

  enum CodingKeys: String, CodingKey {
    case clientName = "client_name"
    case redirectURIs = "redirect_uris"
  }
}

private struct RegistrationResponse: Decodable {
  var clientID: String

  enum CodingKeys: String, CodingKey {
    case clientID = "client_id"
  }
}

private struct OAuthErrorResponse: Decodable {
  var error: String?
  var errorDescription: String?

  enum CodingKeys: String, CodingKey {
    case error
    case errorDescription = "error_description"
  }
}

private extension Data {
  func base64URLEncodedString() -> String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
