import Foundation

struct SureConnectionRequestAuthorizer: RequestAuthorizing {
  private var authorization: () -> SureRequestAuthorization?

  init(authorization: @escaping () -> SureRequestAuthorization) {
    self.authorization = authorization
  }

  init(authorization: SureRequestAuthorization?) {
    self.authorization = { authorization }
  }

  func authorize(_ request: inout URLRequest) {
    request.setValue(nil, forHTTPHeaderField: "Authorization")
    request.setValue(nil, forHTTPHeaderField: "X-Api-Key")

    switch authorization() {
    case .bearer(let token) where !token.isEmpty:
      request.setValue(
        "Bearer \(token)",
        forHTTPHeaderField: "Authorization"
      )
    case .apiKey(let key) where !key.isEmpty:
      request.setValue(key, forHTTPHeaderField: "X-Api-Key")
    case .bearer, .apiKey, nil:
      break
    }
  }
}

enum SureRequestAuthorization: Equatable, Sendable {
  case bearer(String)
  case apiKey(String)
}
