import Foundation
import Testing
@testable import Sure

@Suite("OAuth HTTP client")
struct OAuthHTTPClientTests {
  @Test("Normalizes safe HTTPS servers and rejects unsafe values")
  func serverURLValidation() throws {
    let server = try OAuthServerURL("HTTPS://Sure.Example:443/self-hosted/")
    #expect(server.url.absoluteString == "https://sure.example/self-hosted")

    let invalidValues = [
      "http://sure.example",
      "https://user@sure.example",
      "https://sure.example?token=private",
      "https://sure.example#fragment",
      "https:///missing-host",
      "https://sure.example/%2E%2E/private"
    ]
    for value in invalidValues {
      do {
        _ = try OAuthServerURL(value)
        #expect(Bool(false))
      } catch let error as PasskeyOAuthError {
        #expect(error == .invalidServerURL)
      }
    }
  }

  @Test("Registers once and caches the client ID by normalized server")
  func dynamicRegistrationAndCache() async throws {
    let stub = HTTPDataTransportStub([
      try .http(json: #"{"client_id":"client-123"}"#, status: 201)
    ])
    let cache = OAuthClientIDStoreFake()
    let client = OAuthHTTPClient(dataTransport: stub, clientIDStore: cache)
    let redirectURL = try #require(URL(
      string: "http://127.0.0.1:53921/oauth/callback"
    ))
    let server = try OAuthServerURL("https://sure.example/self-hosted/")

    let registered = try await client.clientID(server: server, redirectURL: redirectURL)
    let cached = try await client.clientID(
      server: OAuthServerURL("https://SURE.EXAMPLE:443/self-hosted"),
      redirectURL: redirectURL
    )

    #expect(registered == "client-123")
    #expect(cached == "client-123")
    #expect(cache.clientID(for: server.url) == "client-123")
    let requests = await stub.requests()
    #expect(requests.count == 1)
    let request = try #require(requests.first)
    #expect(request.url?.absoluteString == "https://sure.example/self-hosted/register")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    let body = try JSONDecoder().decode(
      RegistrationBody.self,
      from: try #require(request.httpBody)
    )
    #expect(body.clientName == "Sure for Apple")
    #expect(body.redirectURIs == [redirectURL.absoluteString])
  }

  @Test("Builds the documented authorization URL")
  func authorizationURL() throws {
    let server = try OAuthServerURL("https://sure.example/self-hosted")
    let redirectURL = try #require(URL(
      string: "http://127.0.0.1:53921/oauth/callback"
    ))

    let url = try OAuthAuthorizationURL.make(
      server: server,
      clientID: "client-123",
      redirectURL: redirectURL,
      challenge: "challenge-123",
      state: "state-123"
    )

    #expect(url.path == "/self-hosted/oauth/authorize")
    #expect(queryValues(url) == [
      "client_id": "client-123",
      "redirect_uri": redirectURL.absoluteString,
      "response_type": "code",
      "scope": "read_write",
      "code_challenge": "challenge-123",
      "code_challenge_method": "S256",
      "state": "state-123"
    ])
  }

  @Test("Exchanges an authorization code using a typed form request")
  func authorizationCodeExchange() async throws {
    let stub = HTTPDataTransportStub([
      try .http(json: tokenJSON(access: "access-1", refresh: "refresh-1"))
    ])
    let client = OAuthHTTPClient(
      dataTransport: stub,
      clientIDStore: OAuthClientIDStoreFake()
    )
    let server = try OAuthServerURL("https://sure.example/self-hosted")
    let redirectURL = try #require(URL(
      string: "http://127.0.0.1:53921/oauth/callback"
    ))

    let tokens = try await client.exchangeAuthorizationCode(
      "code-123",
      verifier: "verifier-123",
      clientID: "client-123",
      redirectURL: redirectURL,
      server: server
    )

    #expect(tokens.accessToken == "access-1")
    #expect(tokens.refreshToken == "refresh-1")
    #expect(tokens.tokenType == "Bearer")
    #expect(tokens.expiresIn == 7_200)
    #expect(tokens.createdAt == 1_800_000_000)
    let request = try #require(await stub.requests().first)
    #expect(request.url?.absoluteString == "https://sure.example/self-hosted/oauth/token")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    #expect(
      request.value(forHTTPHeaderField: "Content-Type")
        == "application/x-www-form-urlencoded"
    )
    #expect(try formValues(request) == [
      "grant_type": "authorization_code",
      "code": "code-123",
      "client_id": "client-123",
      "redirect_uri": redirectURL.absoluteString,
      "code_verifier": "verifier-123"
    ])
  }

  @Test("Refreshes with the cached client ID and rotated tokens")
  func refresh() async throws {
    let stub = HTTPDataTransportStub([
      try .http(json: tokenJSON(access: "access-2", refresh: "refresh-2"))
    ])
    let cache = OAuthClientIDStoreFake()
    let server = try OAuthServerURL("https://sure.example")
    cache.setClientID("client-123", for: server.url)
    let client = OAuthHTTPClient(dataTransport: stub, clientIDStore: cache)

    let tokens = try await client.refresh(
      refreshToken: "refresh-1",
      server: server
    )

    #expect(tokens.accessToken == "access-2")
    #expect(tokens.refreshToken == "refresh-2")
    let request = try #require(await stub.requests().first)
    #expect(request.url?.absoluteString == "https://sure.example/oauth/token")
    #expect(try formValues(request) == [
      "grant_type": "refresh_token",
      "refresh_token": "refresh-1",
      "client_id": "client-123"
    ])
  }

  @Test("Revokes with a form body rather than URL credentials")
  func revoke() async throws {
    let stub = HTTPDataTransportStub([try .http(status: 204)])
    let cache = OAuthClientIDStoreFake()
    let server = try OAuthServerURL("https://sure.example")
    cache.setClientID("client-123", for: server.url)
    let client = OAuthHTTPClient(dataTransport: stub, clientIDStore: cache)

    try await client.revoke(token: "access-private", server: server)

    let request = try #require(await stub.requests().first)
    let requestURL = try #require(request.url?.absoluteString)
    #expect(requestURL == "https://sure.example/oauth/revoke")
    #expect(!requestURL.contains("access-private"))
    #expect(try formValues(request) == [
      "token": "access-private",
      "client_id": "client-123"
    ])
  }

  @Test("Requires a cached registration for refresh without networking")
  func missingRegistration() async throws {
    let stub = HTTPDataTransportStub([])
    let client = OAuthHTTPClient(
      dataTransport: stub,
      clientIDStore: OAuthClientIDStoreFake()
    )

    do {
      _ = try await client.refresh(
        refreshToken: "refresh-1",
        server: OAuthServerURL("https://sure.example")
      )
      #expect(Bool(false))
    } catch let error as PasskeyOAuthError {
      #expect(error == .missingClientRegistration)
    }
    #expect((await stub.requests()).isEmpty)
  }

  @Test("Rejects empty access tokens and normalizes empty refresh tokens")
  func tokenValidation() async throws {
    let stub = HTTPDataTransportStub([
      try .http(json: #"{"access_token":"","refresh_token":"refresh-1"}"#),
      try .http(json: #"{"access_token":"access-1","refresh_token":""}"#)
    ])
    let client = OAuthHTTPClient(
      dataTransport: stub,
      clientIDStore: OAuthClientIDStoreFake()
    )
    let server = try OAuthServerURL("https://sure.example")
    let redirectURL = try #require(URL(
      string: "http://127.0.0.1:53921/oauth/callback"
    ))

    do {
      _ = try await client.exchangeAuthorizationCode(
        "code-1",
        verifier: "verifier-1",
        clientID: "client-123",
        redirectURL: redirectURL,
        server: server
      )
      #expect(Bool(false))
    } catch let error as PasskeyOAuthError {
      #expect(error == .invalidResponse)
    }

    let tokens = try await client.exchangeAuthorizationCode(
      "code-2",
      verifier: "verifier-2",
      clientID: "client-123",
      redirectURL: redirectURL,
      server: server
    )
    #expect(tokens.accessToken == "access-1")
    #expect(tokens.refreshToken == nil)
  }

  @Test("Maps typed server, malformed, and transport failures without raw bodies")
  func failures() async throws {
    let server = try OAuthServerURL("https://sure.example")
    let redirectURL = try #require(URL(
      string: "http://127.0.0.1:53921/oauth/callback"
    ))

    let serverStub = HTTPDataTransportStub([
      try .http(
        json: #"{"error":"invalid_grant","error_description":"Authorization code expired"}"#,
        status: 400
      )
    ])
    do {
      _ = try await OAuthHTTPClient(
        dataTransport: serverStub,
        clientIDStore: OAuthClientIDStoreFake()
      ).exchangeAuthorizationCode(
        "code-private",
        verifier: "verifier-private",
        clientID: "client-123",
        redirectURL: redirectURL,
        server: server
      )
      #expect(Bool(false))
    } catch let error as PasskeyOAuthError {
      #expect(error == .server(400))
      #expect(!error.localizedDescription.contains("Authorization code expired"))
      #expect(!error.localizedDescription.contains("code-private"))
      #expect(!error.localizedDescription.contains("verifier-private"))
    }

    let malformedStub = HTTPDataTransportStub([
      try .http(json: #"{"access_token":42,"private":"must-not-leak"}"#)
    ])
    do {
      _ = try await OAuthHTTPClient(
        dataTransport: malformedStub,
        clientIDStore: OAuthClientIDStoreFake()
      ).exchangeAuthorizationCode(
        "code-123",
        verifier: "verifier-123",
        clientID: "client-123",
        redirectURL: redirectURL,
        server: server
      )
      #expect(Bool(false))
    } catch let error as PasskeyOAuthError {
      #expect(error == .invalidResponse)
      #expect(!error.localizedDescription.contains("must-not-leak"))
    }

    let transportStub = HTTPDataTransportStub([
      .failure(OAuthHTTPClientTestError.expected)
    ])
    do {
      _ = try await OAuthHTTPClient(
        dataTransport: transportStub,
        clientIDStore: OAuthClientIDStoreFake()
      ).exchangeAuthorizationCode(
        "code-123",
        verifier: "verifier-123",
        clientID: "client-123",
        redirectURL: redirectURL,
        server: server
      )
      #expect(Bool(false))
    } catch let error as PasskeyOAuthError {
      #expect(error == .transport)
    }
  }

  private func queryValues(_ url: URL) -> [String: String] {
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    return Dictionary(uniqueKeysWithValues: items.compactMap { item in
      item.value.map { (item.name, $0) }
    })
  }

  private func formValues(_ request: URLRequest) throws -> [String: String] {
    let body = String(
      decoding: try #require(request.httpBody),
      as: UTF8.self
    )
    let url = try #require(URL(string: "https://form.invalid/?\(body)"))
    return queryValues(url)
  }

  private func tokenJSON(access: String, refresh: String) -> String {
    """
    {
      "access_token": "\(access)",
      "refresh_token": "\(refresh)",
      "token_type": "Bearer",
      "expires_in": "7200",
      "created_at": 1800000000
    }
    """
  }
}

@MainActor
@Suite("OAuth workflow")
struct OAuthWorkflowTests {
  @Test("Treats remote revocation as best effort")
  func bestEffortRevoke() async throws {
    let stub = HTTPDataTransportStub([
      .failure(OAuthHTTPClientTestError.expected)
    ])
    let cache = OAuthClientIDStoreFake()
    let server = try OAuthServerURL("https://sure.example")
    cache.setClientID("client-123", for: server.url)
    let service = PasskeyOAuthService(oauthClient: OAuthHTTPClient(
      dataTransport: stub,
      clientIDStore: cache
    ))

    await service.revoke(token: "access-private", serverURL: server.url.absoluteString)

    #expect((await stub.requests()).count == 1)
  }
}

private final class OAuthClientIDStoreFake: OAuthClientIDStoring, @unchecked Sendable {
  private var values: [URL: String] = [:]

  func clientID(for serverURL: URL) -> String? {
    values[serverURL]
  }

  func setClientID(_ clientID: String, for serverURL: URL) {
    values[serverURL] = clientID
  }
}

private struct RegistrationBody: Decodable {
  var clientName: String
  var redirectURIs: [String]

  enum CodingKeys: String, CodingKey {
    case clientName = "client_name"
    case redirectURIs = "redirect_uris"
  }
}

private enum OAuthHTTPClientTestError: Error {
  case expected
}
