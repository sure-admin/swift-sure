import Foundation

enum SureToolDelegationError: Error, Equatable, LocalizedError {
  case unavailable
  case mobileUnavailable
  case argumentsUnsupportedLocally
  case bearerRequired
  case invalidArguments
  case invalidResponse
  case rpc(Int)
  case toolFailed
  case responseTooLarge

  var errorDescription: String? {
    switch self {
    case .unavailable: "This tool is unavailable or disabled for this client."
    case .mobileUnavailable: "This tool requires Sure. Local mode cannot contact the server."
    case .argumentsUnsupportedLocally: "The local account snapshot does not support these arguments."
    case .bearerRequired: "Sure tools require bearer authorization with read_write scope. API keys are not supported by Sure MCP."
    case .invalidArguments: "Tool arguments must be a valid JSON object."
    case .invalidResponse: "Sure returned an invalid tool response."
    case .rpc: "Sure rejected the tool request."
    case .toolFailed: "The Sure tool could not complete the request."
    case .responseTooLarge: "The tool response is too large. Narrow the request or request a smaller page."
    }
  }
}
