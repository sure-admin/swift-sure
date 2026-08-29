import Foundation

struct OAuthServerURL: Equatable, Sendable {
  let url: URL

  init(_ value: String) throws {
    guard let candidate = URL(string: value) else {
      throw PasskeyOAuthError.invalidServerURL
    }
    do {
      url = try SureRequestContext(baseURL: candidate, authorization: nil).baseURL
    } catch {
      throw PasskeyOAuthError.invalidServerURL
    }
  }

  func appending(path: String) -> URL {
    url.appending(path: path)
  }
}
