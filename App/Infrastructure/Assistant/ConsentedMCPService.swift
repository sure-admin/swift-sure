import Foundation

/// Captured before model execution. Approval never rebinds a pending request to
/// a new server/account, and both discovery and execution pass through the gate.
struct ConsentedMCPService {
  var client: SureMCPClient
  var server: URL
  var access: MCPAccessStore

  func discover() async throws -> String {
    try await access.authorize(server: server, operation: "Read available Sure tools", arguments: "No financial arguments. This reads tool names and schemas.")
    let definitions = try await client.availableTools()
    let data = try JSONEncoder().encode(definitions)
    guard data.count <= 65_536 else { throw SureToolDelegationError.responseTooLarge }
    return String(decoding: data, as: UTF8.self)
  }

  func call(name: String, argumentsJSON: String) async throws -> String {
    try Task.checkCancellation()
    guard let tool = SureToolInventory(rawValue: name), tool.permitsServerDelegation else {
      throw SureToolDelegationError.unavailable
    }
    guard argumentsJSON.utf8.count <= 16_384 else { throw SureToolDelegationError.invalidArguments }
    let arguments: [String: ToolJSONValue]
    do {
      arguments = try JSONDecoder().decode([String: ToolJSONValue].self, from: Data(argumentsJSON.utf8))
    } catch { throw SureToolDelegationError.invalidArguments }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let reviewedArguments = String(decoding: try encoder.encode(arguments), as: UTF8.self)
    try await access.authorize(server: server, operation: name, arguments: reviewedArguments)
    let content = try await client.call(tool, arguments: arguments)
    return String(decoding: try JSONEncoder().encode(Result(content: content)), as: UTF8.self)
  }

  private struct Result: Encodable {
    var source = "Sure server via MCP"
    var content: String
  }
}
