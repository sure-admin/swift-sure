struct SureMCPToolDefinition: Codable, Sendable {
  var name: String
  var description: String
  var inputSchema: ToolJSONValue
}
