import Foundation

actor MobileSSOHTTPClient {
  private var dataTransport: any HTTPDataTransport

  init(dataTransport: any HTTPDataTransport) {
    self.dataTransport = dataTransport
  }

  func exchange(code: String, server: OAuthServerURL) async throws -> PasskeyOAuthTokens {
    try await tokens(
      request: jsonRequest(
        url: server.appending(path: "api/v1/auth/sso_exchange"),
        body: SSOExchangeRequest(code: code)
      )
    )
  }

  func refresh(
    refreshToken: String,
    deviceID: String,
    server: OAuthServerURL
  ) async throws -> PasskeyOAuthTokens {
    try await tokens(
      request: jsonRequest(
        url: server.appending(path: "api/v1/auth/refresh"),
        body: MobileRefreshRequest(
          refreshToken: refreshToken,
          device: MobileRefreshDevice(deviceID: deviceID)
        )
      )
    )
  }

  private func jsonRequest<Body: Encodable>(url: URL, body: Body) -> URLRequest {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONEncoder().encode(body)
    return request
  }

  private func tokens(request: URLRequest) async throws -> PasskeyOAuthTokens {
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await dataTransport.data(for: request)
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as URLError where error.code == .cancelled {
      throw CancellationError()
    } catch {
      throw MobileSSOError.transport
    }
    guard let response = response as? HTTPURLResponse else {
      throw MobileSSOError.invalidCallback
    }
    guard 200..<300 ~= response.statusCode else {
      throw MobileSSOError.server(response.statusCode)
    }
    do {
      return try JSONDecoder().decode(PasskeyOAuthTokens.self, from: data)
    } catch {
      throw MobileSSOError.invalidCallback
    }
  }
}

private struct SSOExchangeRequest: Encodable {
  var code: String
}

private struct MobileRefreshRequest: Encodable {
  var refreshToken: String
  var device: MobileRefreshDevice

  enum CodingKeys: String, CodingKey {
    case refreshToken = "refresh_token"
    case device
  }
}

private struct MobileRefreshDevice: Encodable {
  var deviceID: String

  enum CodingKeys: String, CodingKey {
    case deviceID = "device_id"
  }
}
