import Foundation

struct SureConnectionRequestAuthorizer: RequestAuthorizing {
  private var authorization: () -> SureRequestAuthorization

  init(connection: SureConnection) {
    authorization = {
      if connection.isPasskeyConnected {
        return .bearer(connection.accessToken)
      }
      return .apiKey(connection.apiKey)
    }
  }

  init(authorization: @escaping () -> SureRequestAuthorization) {
    self.authorization = authorization
  }

  func authorize(_ request: inout URLRequest) {
    switch authorization() {
    case .bearer(let token):
      request.setValue(
        "Bearer \(token)",
        forHTTPHeaderField: "Authorization"
      )
    case .apiKey(let key):
      request.setValue(key, forHTTPHeaderField: "X-Api-Key")
    }
  }
}

enum SureRequestAuthorization {
  case bearer(String)
  case apiKey(String)
}

extension SureAPITransport {
  init(
    connection: SureConnection,
    dataTransport: any HTTPDataTransport = URLSessionHTTPDataTransport(session: .shared),
    timeoutInterval: TimeInterval = 60
  ) {
    self.init(
      baseURL: {
        guard let url = URL(string: connection.serverURL) else {
          throw SureAPIError.invalidURL
        }
        return url
      },
      dataTransport: dataTransport,
      authorizer: SureConnectionRequestAuthorizer(connection: connection),
      timeoutInterval: timeoutInterval
    )
  }
}
