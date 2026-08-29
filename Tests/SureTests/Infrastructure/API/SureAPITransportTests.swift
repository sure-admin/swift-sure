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
    SureConnectionRequestAuthorizer(authorization: { .bearer("synthetic-token") })
      .authorize(&bearerRequest)
    #expect(bearerRequest.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-token")
    #expect(bearerRequest.value(forHTTPHeaderField: "X-Api-Key") == nil)

    var apiKeyRequest = URLRequest(url: url)
    SureConnectionRequestAuthorizer(authorization: { .apiKey("synthetic-key") })
      .authorize(&apiKeyRequest)
    #expect(apiKeyRequest.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(apiKeyRequest.value(forHTTPHeaderField: "X-Api-Key") == "synthetic-key")
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

private struct CreateValueRequest: Codable {
  var value: String
}
