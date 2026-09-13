import Foundation

/// The caller chooses the destination before model execution. Model-generated
/// names/arguments cannot grant remote access or cause a local-to-remote fallback.
struct AssistantToolRouter {
  var destination: Destination

  enum Destination {
    case localSnapshot
    /// Construct only following an explicit user action allowing Sure tool access.
    case sure(any SureToolDelegating)
  }

  func call(
    name: String,
    arguments: [String: ToolJSONValue],
    localAccounts: () async throws -> String
  ) async throws -> String {
    try Task.checkCancellation()
    guard let tool = SureToolInventory(rawValue: name) else {
      throw SureToolDelegationError.unavailable
    }
    let result: String
    switch destination {
    case .localSnapshot:
      guard tool.isAvailableOnMobile else { throw SureToolDelegationError.mobileUnavailable }
      guard arguments.isEmpty else { throw SureToolDelegationError.argumentsUnsupportedLocally }
      result = try await localAccounts()
    case .sure(let delegate):
      guard tool.permitsServerDelegation else { throw SureToolDelegationError.unavailable }
      result = try await delegate.call(tool, arguments: arguments)
    }
    try Task.checkCancellation()
    return result
  }
}
