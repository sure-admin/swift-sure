import Foundation
import Testing
@testable import Sure

@Suite("Sure tool delegation")
struct SureToolDelegationTests {
  @Test func inventoryPolicy() {
    #expect(SureToolInventory.allCases.count == 26)
    #expect(SureToolInventory.allCases.filter(\.isAvailableOnMobile) == [.getAccounts])
    #expect(SureToolInventory.allCases.filter(\.requiresPreview).count == 7)
    #expect(SureToolInventory.allCases.filter(\.permitsServerDelegation).count == 16)
    #expect(!SureToolInventory.updateBudget.permitsServerDelegation)
    #expect(SureToolInventory(rawValue: "future_tool") == nil)
  }

  @Test func localRoutingCannotEscalate() async throws {
    let router = AssistantToolRouter(destination: .localSnapshot)
    #expect(try await router.call(name: "get_accounts", arguments: [:], localAccounts: { "snapshot" }) == "snapshot")
    await #expect(throws: SureToolDelegationError.mobileUnavailable) {
      try await router.call(name: "get_budget", arguments: [:], localAccounts: { Issue.record("Unexpected local execution"); return "" })
    }
    await #expect(throws: SureToolDelegationError.argumentsUnsupportedLocally) {
      try await router.call(name: "get_accounts", arguments: ["include_balance_series": .bool(true)], localAccounts: { "" })
    }
    await #expect(throws: SureToolDelegationError.unavailable) {
      try await router.call(name: "unknown", arguments: [:], localAccounts: { "" })
    }
  }

  @Test func delegatesStructuredArgumentsAndPreservesPagination() async throws {
    let stub = try responses(call: "mcp-success")
    let client = try makeClient(stub)
    let result = try await AssistantToolRouter(destination: .sure(client)).call(
      name: "get_accounts", arguments: ["include_balance_series": .bool(true)],
      localAccounts: { Issue.record("Remote invocation must not execute locally"); return "" }
    )
    #expect(result == #"{"accounts":[],"pagination":{"page":1,"total_pages":2}}"#)
    let requests = await stub.requests()
    #expect(requests.count == 4)
    #expect(requests.allSatisfy { $0.url?.absoluteString == "https://sure.example/subpath/mcp" })
    #expect(requests.allSatisfy { $0.httpMethod == "POST" })
    #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "MCP-Protocol-Version") == "2025-06-18" })
    #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "X-Api-Key") == nil })
    let body = try JSONDecoder().decode(ToolJSONValue.self, from: #require(requests.last?.httpBody))
    guard case .object(let object) = body else { Issue.record("Expected object"); return }
    #expect(object["method"] == .string("tools/call"))
    #expect(object["params"] == .object(["name": .string("get_accounts"), "arguments": .object(["include_balance_series": .bool(true)])]))
  }

  @Test func discoveryFiltersWrites() async throws {
    let stub = try responses(call: nil)
    #expect(try await makeClient(stub).availableTools().map(\.name) == ["get_accounts"])
  }

  @Test func unsupportedAuthorizationAndWritesNeverSend() async throws {
    let stub = HTTPDataTransportStub([])
    await #expect(throws: SureToolDelegationError.bearerRequired) {
      try await makeClient(stub, authorization: .apiKey("synthetic")).call(.getAccounts, arguments: [:])
    }
    await #expect(throws: SureToolDelegationError.unavailable) {
      try await makeClient(stub).call(.updateTransaction, arguments: [:])
    }
    #expect(await stub.requests().isEmpty)
  }

  @Test func absentPreviewToolIsNotCalled() async throws {
    let stub = try responses(call: nil, list: "mcp-empty")
    await #expect(throws: SureToolDelegationError.unavailable) {
      try await makeClient(stub).call(.getInsights, arguments: [:])
    }
    #expect(await stub.requests().count == 3)
  }

  @Test(arguments: ["mcp-error", "mcp-tool-error", "mcp-malformed"])
  func separatesFailures(fixture: String) async throws {
    let stub = try responses(call: fixture)
    let expected: SureToolDelegationError = switch fixture {
    case "mcp-error": .rpc(-32602)
    case "mcp-tool-error": .toolFailed
    default: .invalidResponse
    }
    await #expect(throws: expected) {
      try await makeClient(stub).call(.getAccounts, arguments: [:])
    }
    #expect(!expected.localizedDescription.contains("diagnostic"))
  }

  @Test func mismatchedIDAndAmbiguousEnvelopeAreRejected() async throws {
    for json in [
      #"{"jsonrpc":"2.0","id":"wrong","result":{}}"#,
      #"{"jsonrpc":"2.0","id":"00000000-0000-0000-0000-000000000001","result":{"protocolVersion":"2025-06-18","capabilities":{"tools":{}}},"error":{"code":-32600}}"#
    ] {
      let stub = HTTPDataTransportStub([try .http(json: json)])
      await #expect(throws: (any Error).self) {
        try await makeClient(stub).call(.getAccounts, arguments: [:])
      }
      #expect(await stub.requests().count == 1)
    }
  }

  @Test func cancellationPropagatesWithoutRetry() async throws {
    let stub = HTTPDataTransportStub([.failure(URLError(.cancelled))])
    await #expect(throws: CancellationError.self) {
      try await makeClient(stub).call(.getAccounts, arguments: [:])
    }
    #expect(await stub.requests().count == 1)
  }

  @Test func sessionChangeDiscardsDiscovery() async throws {
    let first = try context(.bearer("synthetic-first"))
    let second = try context(.bearer("synthetic-second"))
    let session = SureSession(context: first)
    let stub = SessionChangingTransport(session: session, replacement: second)
    let client = SureMCPClient(session: session, dataTransport: stub, makeID: { testID })
    await #expect(throws: CancellationError.self) {
      try await client.call(.getAccounts, arguments: [:])
    }
    #expect(await stub.count == 1)
  }

  @Test func preparedSessionCannotSwitchAccounts() async throws {
    let session = SureSession(context: try context(.bearer("first")))
    let stub = HTTPDataTransportStub([])
    let client = SureMCPClient(session: session, dataTransport: stub, makeID: { testID })
    let bound = try await client.boundToCurrentSession()
    await session.replaceContext(with: try context(.bearer("second")))
    await #expect(throws: CancellationError.self) {
      try await bound.call(.getAccounts, arguments: [:])
    }
    #expect(await stub.requests().isEmpty)
  }

  @Test(arguments: [401, 403, 500])
  func httpFailuresDoNotReplay(status: Int) async throws {
    let stub = HTTPDataTransportStub([try .http(json: "{}", status: status)])
    let expected: SureAPIError = switch status {
    case 401: .unauthorized
    case 403: .forbidden
    default: .server(status)
    }
    await #expect(throws: expected) {
      try await makeClient(stub).call(.getAccounts, arguments: [:])
    }
    #expect(await stub.requests().count == 1)
  }

  @Test func paginatedDiscoveryIsNotSilentlyTruncated() async throws {
    let stub = HTTPDataTransportStub([
      try .http(fixture: "mcp-initialize"), try .http(status: 204),
      try .http(json: #"{"jsonrpc":"2.0","id":"00000000-0000-0000-0000-000000000001","result":{"tools":[],"nextCursor":"page2"}}"#)
    ])
    await #expect(throws: SureToolDelegationError.invalidResponse) {
      try await makeClient(stub).availableTools()
    }
  }

  @Test func JSONPreservesDecimalAndNestedSchema() throws {
    let data = Data(#"{"amount":9007199254740993,"balance":-123.456,"items":[null,true,"value"],"schema":{"type":"object"}}"#.utf8)
    let value = try JSONDecoder().decode(ToolJSONValue.self, from: data)
    guard case .object(let object) = value else { Issue.record("Expected object"); return }
    #expect(object["amount"] == .number(Decimal(string: "9007199254740993")!))
    #expect(try JSONDecoder().decode(ToolJSONValue.self, from: JSONEncoder().encode(value)) == value)
  }

  private func responses(call: String?, list: String = "mcp-tools") throws -> HTTPDataTransportStub {
    var queue: [HTTPDataTransportStub.Result] = [
      try .http(fixture: "mcp-initialize"), try .http(status: 204), try .http(fixture: list)
    ]
    if let call { queue.append(try .http(fixture: call)) }
    return HTTPDataTransportStub(queue)
  }

  private func makeClient(_ stub: HTTPDataTransportStub, authorization: SureRequestAuthorization = .bearer("synthetic")) throws -> SureMCPClient {
    SureMCPClient(session: SureSession(context: try context(authorization)), dataTransport: stub, makeID: { testID })
  }

  private func context(_ authorization: SureRequestAuthorization) throws -> SureRequestContext {
    try SureRequestContext(baseURL: URL(string: "https://sure.example/subpath")!, authorization: authorization)
  }
}

private let testID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

private actor SessionChangingTransport: HTTPDataTransport {
  var session: SureSession
  var replacement: SureRequestContext
  var count = 0

  init(session: SureSession, replacement: SureRequestContext) {
    self.session = session
    self.replacement = replacement
  }

  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    count += 1
    await session.replaceContext(with: replacement)
    return (try APIFixture.data(named: "mcp-initialize"), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
  }
}
