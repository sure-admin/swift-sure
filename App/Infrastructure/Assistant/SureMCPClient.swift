import Foundation

/// One bounded handshake/discovery/call per invocation, bound to one authenticated
/// context. No cached capabilities can survive logout, account changes or token rotation.
struct SureMCPClient: SureToolDelegating {
  var session: any SureRequestContextProviding
  var dataTransport: any HTTPDataTransport
  var makeID: @Sendable () -> UUID

  func call(_ tool: SureToolInventory, arguments: [String: ToolJSONValue]) async throws -> String {
    guard tool.permitsServerDelegation else { throw SureToolDelegationError.unavailable }
    let transport = try await boundTransport()
    let listing = try await discover(using: transport)
    guard let advertised = listing.first(where: { $0.name == tool.rawValue }) else {
      throw SureToolDelegationError.unavailable
    }
    guard case .object(let schema) = advertised.inputSchema, schema["type"] == .string("object") else {
      throw SureToolDelegationError.invalidResponse
    }
    let result: CallResult = try await send(
      method: .call,
      params: CallParameters(name: tool.rawValue, arguments: arguments),
      transport: transport
    )
    guard result.isError != true else { throw SureToolDelegationError.toolFailed }
    guard !result.content.isEmpty, result.content.allSatisfy({ $0.type == "text" && $0.text != nil }) else {
      throw SureToolDelegationError.invalidResponse
    }
    // Preserve JSON text and pagination metadata exactly. Do not flatten, sum,
    // auto-page, interpret embedded instructions, or substitute chat prose.
    let text = result.content.map { $0.text! }.joined(separator: "\n")
    guard text.utf8.count <= 65_536 else { throw SureToolDelegationError.responseTooLarge }
    return text
  }

  /// Pin an entire model session, including its discovery and later invocations,
  /// so arguments generated for one connection cannot be sent to another.
  func boundToCurrentSession() async throws -> SureMCPClient {
    let context = try await session.requestContext()
    guard case .bearer = context.authorization else { throw SureToolDelegationError.bearerRequired }
    return SureMCPClient(
      session: BoundSession(session: session, context: context),
      dataTransport: dataTransport, makeID: makeID
    )
  }

  func availableTools() async throws -> [SureMCPToolDefinition] {
    let transport = try await boundTransport()
    return try await discover(using: transport).filter {
      SureToolInventory(rawValue: $0.name)?.permitsServerDelegation == true
    }
  }

  private func boundTransport() async throws -> SureAPITransport {
    try Task.checkCancellation()
    let context = try await session.requestContext()
    guard case .bearer = context.authorization else { throw SureToolDelegationError.bearerRequired }
    return SureAPITransport(
      session: BoundSession(session: session, context: context),
      dataTransport: MCPDataTransport(base: dataTransport),
      timeoutInterval: 30
    )
  }

  private func discover(using transport: SureAPITransport) async throws -> [SureMCPToolDefinition] {
    let initialized: Initialization = try await send(
      method: .initialize, params: InitializeParameters(), transport: transport
    )
    guard initialized.protocolVersion == "2025-06-18",
          initialized.capabilities.tools != nil else {
      throw SureToolDelegationError.invalidResponse
    }
    try await transport.send(APIRequest<Void>(
      method: .post, pathComponents: ["mcp"], body: InitializedNotification(),
      expectedStatusCodes: [204]
    ))
    // Sure supports stateless requests without Mcp-Session-Id. Do not persist
    // the handshake's session ID or reuse discovery across authenticated contexts.
    let listing: ToolList = try await send(method: .list, params: EmptyParameters(), transport: transport)
    guard listing.nextCursor == nil,
          Set(listing.tools.map(\.name)).count == listing.tools.count else {
      throw SureToolDelegationError.invalidResponse
    }
    return listing.tools
  }

  private func send<Parameters: Encodable, Result: Decodable>(
    method: Method, params: Parameters, transport: SureAPITransport
  ) async throws -> Result {
    let id = makeID().uuidString
    let response: Response<Result> = try await transport.send(APIRequest(
      method: .post, pathComponents: ["mcp"],
      body: Request(id: id, method: method, params: params)
    ))
    try Task.checkCancellation()
    guard response.jsonrpc == "2.0", response.id == id,
          (response.result != nil) != (response.error != nil) else {
      throw SureToolDelegationError.invalidResponse
    }
    if let error = response.error { throw SureToolDelegationError.rpc(error.code) }
    guard let result = response.result else { throw SureToolDelegationError.invalidResponse }
    return result
  }
}

protocol SureToolDelegating {
  func call(_ tool: SureToolInventory, arguments: [String: ToolJSONValue]) async throws -> String
}

private struct BoundSession: SureRequestContextProviding {
  var session: any SureRequestContextProviding
  var context: SureRequestContext

  func requestContext() async throws -> SureRequestContext {
    guard (try? await session.requestContext()) == context else { throw CancellationError() }
    return context
  }
}

private enum Method: String, Encodable {
  case initialize
  case list = "tools/list"
  case call = "tools/call"
}
private struct Request<Parameters: Encodable>: Encodable {
  var jsonrpc = "2.0"
  var id: String
  var method: Method
  var params: Parameters
}
private struct Response<Result: Decodable>: Decodable {
  var jsonrpc: String
  var id: String
  var result: Result?
  var error: RPCError?
}
private struct RPCError: Decodable { var code: Int }
private struct EmptyParameters: Encodable {}
private struct InitializeParameters: Encodable {
  var protocolVersion = "2025-06-18"
  var capabilities = EmptyParameters()
  var clientInfo = ClientInfo()
}
private struct ClientInfo: Encodable {
  var name = "sure-swift"
  var version = "1.0"
}
private struct Initialization: Decodable {
  var protocolVersion: String
  var capabilities: Capabilities
  struct Capabilities: Decodable { var tools: ToolJSONValue? }
}
private struct ToolList: Decodable {
  var tools: [SureMCPToolDefinition]
  var nextCursor: String?
}
private struct CallParameters: Encodable {
  var name: String
  var arguments: [String: ToolJSONValue]
}
private struct CallResult: Decodable {
  var content: [Content]
  var isError: Bool?
  struct Content: Decodable {
    var type: String
    var text: String?
  }
}

private struct InitializedNotification: Encodable {
  var jsonrpc = "2.0"
  var method = "notifications/initialized"
}

private struct MCPDataTransport: HTTPDataTransport {
  var base: any HTTPDataTransport

  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    var request = request
    request.setValue("2025-06-18", forHTTPHeaderField: "MCP-Protocol-Version")
    request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
    let response = try await base.data(for: request)
    // Bound decoding work. The pinned Sure endpoint returns JSON, not an SSE stream.
    guard response.0.count <= 1_048_576 else { throw SureAPIError.invalidResponse }
    return response
  }
}
