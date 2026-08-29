import Foundation

struct SureRequestContext: Equatable, Sendable {
  let baseURL: URL
  let authorization: SureRequestAuthorization?

  init(baseURL: URL, authorization: SureRequestAuthorization?) throws {
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
          let scheme = components.scheme?.lowercased(),
          let host = components.host,
          !host.isEmpty,
          scheme == "https" || Self.allowsDevelopmentHTTP(scheme: scheme, host: host),
          components.user == nil,
          components.password == nil,
          components.query == nil,
          components.fragment == nil else {
      throw SureRequestContextError.invalidBaseURL
    }

    if let authorization {
      switch authorization {
      case .bearer(let token) where token.isEmpty:
        throw SureRequestContextError.invalidAuthorization
      case .apiKey(let key) where key.isEmpty:
        throw SureRequestContextError.invalidAuthorization
      default:
        break
      }
    }

    let pathSegments = components.percentEncodedPath.split(
      separator: "/",
      omittingEmptySubsequences: true
    )
    for segment in pathSegments {
      guard let decoded = String(segment).removingPercentEncoding,
            decoded != ".",
            decoded != ".." else {
        throw SureRequestContextError.invalidBaseURL
      }
    }

    components.scheme = scheme
    components.host = host.lowercased()
    if scheme == "https", components.port == 443 {
      components.port = nil
    }
    if components.percentEncodedPath == "/" {
      components.percentEncodedPath = ""
    } else {
      while components.percentEncodedPath.hasSuffix("/") {
        components.percentEncodedPath.removeLast()
      }
    }
    guard let normalizedBaseURL = components.url else {
      throw SureRequestContextError.invalidBaseURL
    }

    self.baseURL = normalizedBaseURL
    self.authorization = authorization
  }

  private static func allowsDevelopmentHTTP(scheme: String, host: String) -> Bool {
    #if DEBUG
    guard scheme == "http" else { return false }
    return ["localhost", "127.0.0.1", "::1"].contains(host.lowercased())
    #else
    return false
    #endif
  }
}

enum SureRequestContextError: LocalizedError, Equatable {
  case invalidAuthorization
  case invalidBaseURL

  var errorDescription: String? {
    switch self {
    case .invalidAuthorization:
      "The stored Sure authorization is invalid."
    case .invalidBaseURL:
      "The Sure server URL is invalid."
    }
  }
}
