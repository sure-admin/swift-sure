import Foundation

actor OAuthHTTPClient {
  private var dataTransport: any HTTPDataTransport
  private var clientIDStore: any OAuthClientIDStoring

  init(
    dataTransport: any HTTPDataTransport,
    clientIDStore: any OAuthClientIDStoring
  ) {
    self.dataTransport = dataTransport
    self.clientIDStore = clientIDStore
  }

  func clientID(server: OAuthServerURL, redirectURL: URL) async throws -> String {
    if let saved = clientIDStore.clientID(for: server.url), !saved.isEmpty {
      return saved
    }

    var request = URLRequest(url: server.appending(path: "register"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    do {
      request.httpBody = try JSONEncoder().encode(OAuthRegistrationRequest(
        clientName: "Sure for Apple",
        redirectURIs: [redirectURL.absoluteString]
      ))
    } catch {
      throw PasskeyOAuthError.invalidResponse
    }

    let data = try await responseData(for: request)
    let response: OAuthRegistrationResponse
    do {
      response = try JSONDecoder().decode(OAuthRegistrationResponse.self, from: data)
    } catch {
      throw PasskeyOAuthError.invalidResponse
    }
    guard !response.clientID.isEmpty else {
      throw PasskeyOAuthError.invalidResponse
    }
    clientIDStore.setClientID(response.clientID, for: server.url)
    return response.clientID
  }

  func exchangeAuthorizationCode(
    _ code: String,
    verifier: String,
    clientID: String,
    redirectURL: URL,
    server: OAuthServerURL
  ) async throws -> PasskeyOAuthTokens {
    try await token(
      server: server,
      queryItems: [
        URLQueryItem(name: "grant_type", value: "authorization_code"),
        URLQueryItem(name: "code", value: code),
        URLQueryItem(name: "client_id", value: clientID),
        URLQueryItem(name: "redirect_uri", value: redirectURL.absoluteString),
        URLQueryItem(name: "code_verifier", value: verifier)
      ]
    )
  }

  func refresh(
    refreshToken: String,
    server: OAuthServerURL
  ) async throws -> PasskeyOAuthTokens {
    guard let clientID = clientIDStore.clientID(for: server.url),
          !clientID.isEmpty else {
      throw PasskeyOAuthError.missingClientRegistration
    }
    return try await token(
      server: server,
      queryItems: [
        URLQueryItem(name: "grant_type", value: "refresh_token"),
        URLQueryItem(name: "refresh_token", value: refreshToken),
        URLQueryItem(name: "client_id", value: clientID)
      ]
    )
  }

  func revoke(token: String, server: OAuthServerURL) async throws {
    guard let clientID = clientIDStore.clientID(for: server.url),
          !clientID.isEmpty else {
      throw PasskeyOAuthError.missingClientRegistration
    }
    var request = formRequest(
      url: server.appending(path: "oauth/revoke"),
      queryItems: [
        URLQueryItem(name: "token", value: token),
        URLQueryItem(name: "client_id", value: clientID)
      ]
    )
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    _ = try await responseData(for: request)
  }

  private func token(
    server: OAuthServerURL,
    queryItems: [URLQueryItem]
  ) async throws -> PasskeyOAuthTokens {
    var request = formRequest(
      url: server.appending(path: "oauth/token"),
      queryItems: queryItems
    )
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let data = try await responseData(for: request)
    do {
      return try JSONDecoder().decode(PasskeyOAuthTokens.self, from: data)
    } catch {
      throw PasskeyOAuthError.invalidResponse
    }
  }

  private func formRequest(
    url: URL,
    queryItems: [URLQueryItem]
  ) -> URLRequest {
    var components = URLComponents()
    components.queryItems = queryItems
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue(
      "application/x-www-form-urlencoded",
      forHTTPHeaderField: "Content-Type"
    )
    request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
    return request
  }

  private func responseData(for request: URLRequest) async throws -> Data {
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await dataTransport.data(for: request)
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as URLError where error.code == .cancelled {
      throw CancellationError()
    } catch {
      throw PasskeyOAuthError.transport
    }

    guard let response = response as? HTTPURLResponse else {
      throw PasskeyOAuthError.invalidResponse
    }
    guard 200..<300 ~= response.statusCode else {
      throw PasskeyOAuthError.server(response.statusCode)
    }
    return data
  }
}

private struct OAuthRegistrationRequest: Encodable {
  var clientName: String
  var redirectURIs: [String]

  enum CodingKeys: String, CodingKey {
    case clientName = "client_name"
    case redirectURIs = "redirect_uris"
  }
}

private struct OAuthRegistrationResponse: Decodable {
  var clientID: String

  enum CodingKeys: String, CodingKey {
    case clientID = "client_id"
  }
}
