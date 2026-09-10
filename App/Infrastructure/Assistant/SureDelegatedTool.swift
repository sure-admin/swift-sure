#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, macOS 26.0, *)
struct SureDelegatedTool: Tool {
  let name = "call_sure_tool"
  let description = "Execute a read-only Sure tool using a name and JSON object matching schemas returned by discover_sure_tools. User permission is enforced before sending. Never include conversation history or unrelated local data in arguments."
  var service: ConsentedMCPService

  @Generable
  struct Arguments {
    var toolName: String
    var argumentsJSON: String
  }

  func call(arguments: Arguments) async throws -> String {
    try await service.call(name: arguments.toolName, argumentsJSON: arguments.argumentsJSON)
  }
}
#endif
