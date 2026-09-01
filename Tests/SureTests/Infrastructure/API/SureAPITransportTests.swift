import Foundation
import Testing
@testable import Sure

@Suite("Sure API transport")
struct SureAPITransportTests {
  @Test("Builds an encoded authorized request and decodes its response")
  func requestConstruction() async throws {
    let stub = HTTPDataTransportStub([
      try .http(json: #"{"value":"ok"}"#)
    ])
    let transport = SureAPITransport(
      baseURL: try #require(URL(string: "https://sure.example/self-hosted")),
      dataTransport: stub,
      authorizer: HeaderRequestAuthorizer(name: "X-Api-Key", value: "test-key")
    )
    let response = try await transport.send(
      APIRequest<ValueResponse>(
        method: .get,
        pathComponents: ["api", "v1", "items", "space / percent%"],
        queryItems: [URLQueryItem(name: "search", value: "food & drink")]
      )
    )

    #expect(response.value == "ok")
    let request = try #require(await stub.requests().first)
    let url = try #require(request.url)
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    #expect(components.percentEncodedPath == "/self-hosted/api/v1/items/space%20%2F%20percent%25")
    #expect(components.queryItems == [URLQueryItem(name: "search", value: "food & drink")])
    #expect(request.value(forHTTPHeaderField: "X-Api-Key") == "test-key")
    #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == nil)
  }

  @Test("Encodes typed JSON request bodies")
  func requestBody() async throws {
    let stub = HTTPDataTransportStub([
      try .http(json: #"{"value":"created"}"#, status: 201)
    ])
    let transport = makeTransport(stub: stub)
    _ = try await transport.send(
      APIRequest<ValueResponse>(
        method: .post,
        pathComponents: ["api", "v1", "items"],
        body: CreateValueRequest(value: "private & safe"),
        expectedStatusCodes: [201]
      )
    )

    let request = try #require(await stub.requests().first)
    let body = try #require(request.httpBody)
    #expect(try JSONDecoder().decode(CreateValueRequest.self, from: body).value == "private & safe")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
  }

  @Test("Classifies authentication, scope, preview, validation, rate, and server failures")
  func errorClassification() async throws {
    #expect(try await error(status: 401, fixture: "error-unauthorized") == .unauthorized)
    #expect(
      try await error(
        status: 403,
        fixture: "error-insufficient-scope",
        forbiddenResponse: .previewFeatureUnavailable
      ) == .forbidden
    )
    #expect(
      try await error(
        status: 403,
        fixture: "error-preview-disabled",
        forbiddenResponse: .previewFeatureUnavailable
      ) == .previewFeatureUnavailable
    )
    #expect(try await error(status: 422, fixture: "error-validation") == .validation)
    #expect(try await error(status: 429, json: #"{"error":"rate_limit_exceeded"}"#) == .rateLimited)
    #expect(try await error(status: 503, json: #"{"error":"unavailable"}"#) == .server(503))
  }

  @Test("Redacts malformed successful response data as a decoding error")
  func malformedSuccess() async throws {
    let stub = HTTPDataTransportStub([try .http(json: #"{"credential":"must-not-leak"}"#)])
    do {
      let _: ValueResponse = try await makeTransport(stub: stub).send(
        APIRequest(method: .get, pathComponents: ["api", "v1", "items"])
      )
      #expect(Bool(false))
    } catch let error as SureAPIError {
      #expect(error == .decoding)
      #expect(!error.localizedDescription.contains("must-not-leak"))
    }
  }

  @Test("Rejects a bare calendar date where a timestamp is required")
  func rejectsBareTimestampDate() async throws {
    let stub = HTTPDataTransportStub([
      try .http(json: #"{"created_at":"2026-08-29"}"#)
    ])

    await #expect(throws: SureAPIError.decoding) {
      let _: TimestampResponse = try await makeTransport(stub: stub).send(
        APIRequest(method: .get, pathComponents: ["api", "v1", "items"])
      )
    }
  }

  @Test("Preserves cancellation")
  func cancellation() async throws {
    let stub = HTTPDataTransportStub([.failure(CancellationError())])
    do {
      let _: ValueResponse = try await makeTransport(stub: stub).send(
        APIRequest(method: .get, pathComponents: ["api", "v1", "items"])
      )
      #expect(Bool(false))
    } catch is CancellationError {
      #expect(Bool(true))
    }
  }

  @Test("Rejects unsafe base URLs and path components before networking")
  func invalidURLs() async throws {
    let invalidBaseURLs = [
      "https://user@sure.example",
      "https://sure.example?token=private",
      "https://sure.example#fragment",
      "http://sure.example"
    ]
    for value in invalidBaseURLs {
      let stub = HTTPDataTransportStub([])
      let transport = SureAPITransport(
        baseURL: try #require(URL(string: value)),
        dataTransport: stub,
        authorizer: UnauthenticatedRequestAuthorizer()
      )
      await expectInvalidURL(transport, pathComponents: ["api"])
      #expect((await stub.requests()).isEmpty)
    }

    for component in ["", ".", ".."] {
      let stub = HTTPDataTransportStub([])
      await expectInvalidURL(makeTransport(stub: stub), pathComponents: [component])
      #expect((await stub.requests()).isEmpty)
    }

    #if DEBUG
    let loopbackStub = HTTPDataTransportStub([
      try .http(json: #"{"value":"local"}"#)
    ])
    let loopbackTransport = SureAPITransport(
      baseURL: try #require(URL(string: "http://localhost:3000")),
      dataTransport: loopbackStub,
      authorizer: UnauthenticatedRequestAuthorizer()
    )
    let localResponse: ValueResponse = try await loopbackTransport.send(
      APIRequest(method: .get, pathComponents: ["api"])
    )
    #expect(localResponse.value == "local")
    #endif
  }

  @Test("Selects exactly one documented authorization mode")
  func authorizationModes() throws {
    let url = try #require(URL(string: "https://sure.example/api/v1/accounts"))
    var bearerRequest = URLRequest(url: url)
    bearerRequest.setValue("stale-key", forHTTPHeaderField: "X-Api-Key")
    SureConnectionRequestAuthorizer(authorization: { .bearer("synthetic-token") })
      .authorize(&bearerRequest)
    #expect(bearerRequest.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-token")
    #expect(bearerRequest.value(forHTTPHeaderField: "X-Api-Key") == nil)

    var apiKeyRequest = URLRequest(url: url)
    apiKeyRequest.setValue("Bearer stale-token", forHTTPHeaderField: "Authorization")
    SureConnectionRequestAuthorizer(authorization: { .apiKey("synthetic-key") })
      .authorize(&apiKeyRequest)
    #expect(apiKeyRequest.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(apiKeyRequest.value(forHTTPHeaderField: "X-Api-Key") == "synthetic-key")
  }

  @Test("Never emits empty credential headers")
  func emptyAuthorization() throws {
    let url = try #require(URL(string: "https://sure.example/api/v1/accounts"))
    var bearerRequest = URLRequest(url: url)
    SureConnectionRequestAuthorizer(authorization: { .bearer("") })
      .authorize(&bearerRequest)
    #expect(bearerRequest.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(bearerRequest.value(forHTTPHeaderField: "X-Api-Key") == nil)

    var apiKeyRequest = URLRequest(url: url)
    SureConnectionRequestAuthorizer(authorization: { .apiKey("") })
      .authorize(&apiKeyRequest)
    #expect(apiKeyRequest.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(apiKeyRequest.value(forHTTPHeaderField: "X-Api-Key") == nil)
  }

  @Test("A bearer 401 rotates OAuth credentials and retries exactly once")
  func oauthRefreshRetry() async throws {
    let stub = HTTPDataTransportStub([
      try .http(fixture: "error-unauthorized", status: 401),
      try .http(json: #"{"value":"refreshed"}"#)
    ])
    let oldCredentials = try StoredOAuthCredentials(
      accessToken: "expired-access",
      refreshToken: "old-refresh"
    )
    let rejectedContext = try SureRequestContext(
      baseURL: #require(URL(string: "https://sure.example")),
      authorization: .bearer("expired-access")
    )
    let repository = RefreshCredentialRepository(
      session: try StoredOAuthSession(
        serverURL: rejectedContext.baseURL,
        credentials: oldCredentials,
        isVerified: true
      )
    )
    let session = SureSession(context: rejectedContext)
    let recovery = OAuthRefreshCoordinator(
      session: session,
      credentials: repository,
      tokenRefresher: FixedOAuthTokenRefresher(
        tokens: PasskeyOAuthTokens(
          accessToken: "rotated-access",
          refreshToken: "rotated-refresh"
        )
      )
    )
    let transport = SureAPITransport(
      session: session,
      dataTransport: stub,
      unauthorizedRecovery: recovery
    )

    let response: ValueResponse = try await transport.send(
      APIRequest(method: .get, pathComponents: ["api", "v1", "items"])
    )

    #expect(response.value == "refreshed")
    let requests = await stub.requests()
    #expect(requests.count == 2)
    #expect(
      requests.first?.value(forHTTPHeaderField: "Authorization")
        == "Bearer expired-access"
    )
    #expect(
      requests.last?.value(forHTTPHeaderField: "Authorization")
        == "Bearer rotated-access"
    )
    #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "X-Api-Key") == nil })
    #expect(repository.credentials?.accessToken == "rotated-access")
    #expect(repository.credentials?.refreshToken == "rotated-refresh")
    #expect(try await session.requestContext().authorization == .bearer("rotated-access"))
  }

  @Test("Cancellation during OAuth refresh prevents the retry request")
  func cancellationDuringOAuthRefresh() async throws {
    let stub = HTTPDataTransportStub([
      try .http(fixture: "error-unauthorized", status: 401),
      try .http(json: #"{"value":"must-not-be-requested"}"#)
    ])
    let rejectedContext = try SureRequestContext(
      baseURL: #require(URL(string: "https://sure.example")),
      authorization: .bearer("expired-access")
    )
    let repository = RefreshCredentialRepository(
      session: try StoredOAuthSession(
        serverURL: rejectedContext.baseURL,
        credentials: StoredOAuthCredentials(
          accessToken: "expired-access",
          refreshToken: "old-refresh"
        ),
        isVerified: true
      )
    )
    let session = SureSession(context: rejectedContext)
    let refresher = TransportSuspendedOAuthTokenRefresher()
    let recovery = OAuthRefreshCoordinator(
      session: session,
      credentials: repository,
      tokenRefresher: refresher
    )
    let transport = SureAPITransport(
      session: session,
      dataTransport: stub,
      unauthorizedRecovery: recovery
    )
    let requestTask = Task {
      let response: ValueResponse = try await transport.send(
        APIRequest(method: .get, pathComponents: ["api", "v1", "items"])
      )
      return response
    }

    await refresher.waitUntilStarted()
    requestTask.cancel()
    await refresher.complete(with: PasskeyOAuthTokens(
      accessToken: "rotated-access",
      refreshToken: "rotated-refresh"
    ))

    do {
      _ = try await requestTask.value
      #expect(Bool(false))
    } catch is CancellationError {
      #expect(Bool(true))
    }
    #expect((await stub.requests()).count == 1)
  }

  @Test("A late matching 401 adopts the completed OAuth rotation")
  func lateConcurrentUnauthorizedAdoptsRotation() async throws {
    let stub = StaggeredUnauthorizedHTTPDataTransport()
    let rejectedContext = try SureRequestContext(
      baseURL: #require(URL(string: "https://sure.example")),
      authorization: .bearer("expired-access")
    )
    let repository = RefreshCredentialRepository(
      session: try StoredOAuthSession(
        serverURL: rejectedContext.baseURL,
        credentials: StoredOAuthCredentials(
          accessToken: "expired-access",
          refreshToken: "old-refresh"
        ),
        isVerified: true
      )
    )
    let session = SureSession(context: rejectedContext)
    let refresher = TransportSuspendedOAuthTokenRefresher()
    let recovery = OAuthRefreshCoordinator(
      session: session,
      credentials: repository,
      tokenRefresher: refresher
    )
    let transport = SureAPITransport(
      session: session,
      dataTransport: stub,
      unauthorizedRecovery: recovery
    )
    let request = APIRequest<ValueResponse>(
      method: .get,
      pathComponents: ["api", "v1", "items"]
    )
    let first = Task { try await transport.send(request) }
    let second = Task { try await transport.send(request) }

    await stub.waitForExpiredRequestCount(2)
    let releasedFirst = await stub.releaseNextUnauthorized()
    #expect(releasedFirst)
    await refresher.waitUntilStarted()
    await refresher.complete(with: PasskeyOAuthTokens(
      accessToken: "rotated-access",
      refreshToken: "rotated-refresh"
    ))
    await stub.waitForRequestCount(3)
    let releasedSecond = await stub.releaseNextUnauthorized()
    #expect(releasedSecond)

    #expect(try await first.value.value == "refreshed")
    #expect(try await second.value.value == "refreshed")
    let requests = await stub.requests()
    #expect(requests.count == 4)
    #expect(
      requests.filter {
        $0.value(forHTTPHeaderField: "Authorization") == "Bearer expired-access"
      }.count == 2
    )
    #expect(
      requests.filter {
        $0.value(forHTTPHeaderField: "Authorization") == "Bearer rotated-access"
      }.count == 2
    )
    #expect(await refresher.callCount == 1)
  }

  private func error(
    status: Int,
    fixture: String? = nil,
    json: String? = nil,
    forbiddenResponse: APIForbiddenResponse = .authorization
  ) async throws -> SureAPIError {
    let stub = HTTPDataTransportStub([
      try .http(fixture: fixture, json: json, status: status)
    ])
    do {
      let _: ValueResponse = try await makeTransport(stub: stub).send(
        APIRequest(
          method: .get,
          pathComponents: ["api", "v1", "items"],
          forbiddenResponse: forbiddenResponse
        )
      )
      return .invalidResponse
    } catch let error as SureAPIError {
      return error
    }
  }

  private func makeTransport(stub: HTTPDataTransportStub) -> SureAPITransport {
    SureAPITransport(
      baseURL: URL(string: "https://sure.example")!,
      dataTransport: stub,
      authorizer: UnauthenticatedRequestAuthorizer()
    )
  }

  private func expectInvalidURL(
    _ transport: SureAPITransport,
    pathComponents: [String]
  ) async {
    do {
      let _: ValueResponse = try await transport.send(
        APIRequest(method: .get, pathComponents: pathComponents)
      )
      #expect(Bool(false))
    } catch let error as SureAPIError {
      #expect(error == .invalidURL)
    } catch {
      #expect(Bool(false))
    }
  }
}

private struct ValueResponse: Decodable {
  var value: String
}

private struct TimestampResponse: Decodable {
  var createdAt: Date

  enum CodingKeys: String, CodingKey {
    case createdAt = "created_at"
  }
}

private struct CreateValueRequest: Codable {
  var value: String
}

private final class RefreshCredentialRepository: CredentialRepository, @unchecked Sendable {
  private let lock = NSLock()
  private var storedSession: StoredOAuthSession?

  var credentials: StoredOAuthCredentials? {
    lock.withLock { storedSession?.credentials }
  }

  init(session: StoredOAuthSession?) {
    storedSession = session
  }

  func loadCredentials() throws -> StoredCredentialSnapshot {
    lock.withLock {
      StoredCredentialSnapshot(session: storedSession.map(StoredAuthenticatedSession.oauth))
    }
  }

  func replaceSession(_ session: StoredAuthenticatedSession?) throws {
    lock.withLock { storedSession = StoredCredentialSnapshot(session: session).oauthSession }
  }
}

private struct FixedOAuthTokenRefresher: OAuthTokenRefreshing {
  var tokens: PasskeyOAuthTokens

  func refresh(
    refreshToken: String,
    serverURL: String,
    source: OAuthTokenSource
  ) async throws -> PasskeyOAuthTokens {
    tokens
  }
}

private actor TransportSuspendedOAuthTokenRefresher: OAuthTokenRefreshing {
  private(set) var callCount = 0
  private var startContinuation: CheckedContinuation<Void, Never>?
  private var resultContinuation: CheckedContinuation<PasskeyOAuthTokens, Error>?

  func refresh(
    refreshToken: String,
    serverURL: String,
    source: OAuthTokenSource
  ) async throws -> PasskeyOAuthTokens {
    callCount += 1
    startContinuation?.resume()
    startContinuation = nil
    return try await withCheckedThrowingContinuation { continuation in
      resultContinuation = continuation
    }
  }

  func waitUntilStarted() async {
    guard callCount == 0 else { return }
    await withCheckedContinuation { continuation in
      startContinuation = continuation
    }
  }

  func complete(with tokens: PasskeyOAuthTokens) {
    resultContinuation?.resume(returning: tokens)
    resultContinuation = nil
  }
}

private actor StaggeredUnauthorizedHTTPDataTransport: HTTPDataTransport {
  private var recordedRequests: [URLRequest] = []
  private var expiredRequestCount = 0
  private var pendingUnauthorizedResponses: [
    CheckedContinuation<(Data, URLResponse), Never>
  ] = []
  private var expiredCountWaiter: (
    target: Int,
    continuation: CheckedContinuation<Void, Never>
  )?
  private var requestCountWaiter: (
    target: Int,
    continuation: CheckedContinuation<Void, Never>
  )?

  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    recordedRequests.append(request)
    resumeSatisfiedWaiters()

    if request.value(forHTTPHeaderField: "Authorization") == "Bearer expired-access" {
      expiredRequestCount += 1
      resumeSatisfiedWaiters()
      return await withCheckedContinuation { continuation in
        pendingUnauthorizedResponses.append(continuation)
      }
    }

    return Self.response(status: 200, json: #"{"value":"refreshed"}"#)
  }

  func waitForExpiredRequestCount(_ target: Int) async {
    guard expiredRequestCount < target else { return }
    await withCheckedContinuation { continuation in
      expiredCountWaiter = (target, continuation)
    }
  }

  func waitForRequestCount(_ target: Int) async {
    guard recordedRequests.count < target else { return }
    await withCheckedContinuation { continuation in
      requestCountWaiter = (target, continuation)
    }
  }

  func releaseNextUnauthorized() -> Bool {
    guard !pendingUnauthorizedResponses.isEmpty else { return false }
    let continuation = pendingUnauthorizedResponses.removeFirst()
    continuation.resume(returning: Self.response(
      status: 401,
      json: #"{"error":"unauthorized"}"#
    ))
    return true
  }

  func requests() -> [URLRequest] {
    recordedRequests
  }

  private func resumeSatisfiedWaiters() {
    if let waiter = expiredCountWaiter,
       expiredRequestCount >= waiter.target {
      expiredCountWaiter = nil
      waiter.continuation.resume()
    }
    if let waiter = requestCountWaiter,
       recordedRequests.count >= waiter.target {
      requestCountWaiter = nil
      waiter.continuation.resume()
    }
  }

  private static func response(status: Int, json: String) -> (Data, URLResponse) {
    let url = URL(string: "https://sure.example")!
    let response = HTTPURLResponse(
      url: url,
      statusCode: status,
      httpVersion: "HTTP/1.1",
      headerFields: nil
    )!
    return (Data(json.utf8), response)
  }
}
