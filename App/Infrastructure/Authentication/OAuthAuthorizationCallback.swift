import Foundation

struct OAuthAuthorizationCallback: Equatable, Sendable {
  let code: String

  static func parse(_ url: URL, expectedState: String) throws -> OAuthAuthorizationCallback {
    guard let queryItems = URLComponents(
      url: url,
      resolvingAgainstBaseURL: false
    )?.queryItems else {
      throw PasskeyOAuthError.invalidResponse
    }

    let protectedNames = Set(["state", "code", "error", "error_description"])
    var values: [String: String] = [:]
    for item in queryItems where protectedNames.contains(item.name) {
      guard values[item.name] == nil,
            let value = item.value,
            !value.isEmpty else {
        throw PasskeyOAuthError.invalidResponse
      }
      values[item.name] = value
    }

    if values["code"] != nil && values["error"] != nil {
      throw PasskeyOAuthError.invalidResponse
    }
    if values["error_description"] != nil || values["error"] != nil {
      throw PasskeyOAuthError.authorizationRejected
    }
    guard values["state"] == expectedState,
          let code = values["code"] else {
      throw PasskeyOAuthError.invalidResponse
    }
    return OAuthAuthorizationCallback(code: code)
  }
}
