import Foundation

enum OAuthAuthorizationURL {
  static func make(
    server: OAuthServerURL,
    clientID: String,
    redirectURL: URL,
    challenge: String,
    state: String
  ) throws -> URL {
    var components = URLComponents(
      url: server.appending(path: "oauth/authorize"),
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
    guard let url = components?.url else {
      throw PasskeyOAuthError.invalidServerURL
    }
    return url
  }
}
