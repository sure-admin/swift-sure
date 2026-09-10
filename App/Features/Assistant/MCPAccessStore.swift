import Foundation
import Observation

@MainActor
@Observable
final class MCPAccessStore {
  var allowsAutomaticAccess: Bool {
    didSet { preferences.setAllowsAutomaticAccess(allowsAutomaticAccess) }
  }
  private(set) var pendingRequest: Request?
  private var continuation: CheckedContinuation<Void, Error>?
  private var canPresent = false
  private let preferences: any MCPAccessPreferences
  private let makeID: () -> UUID

  init(preferences: any MCPAccessPreferences, makeID: @escaping () -> UUID) {
    self.preferences = preferences
    self.makeID = makeID
    allowsAutomaticAccess = preferences.allowsAutomaticAccess()
  }

  func setPresentationAvailable(_ available: Bool) {
    canPresent = available
    if !available { cancelPending() }
  }

  func authorize(server: URL, operation: String, arguments: String) async throws {
    try Task.checkCancellation()
    guard canPresent else { throw CancellationError() }
    if allowsAutomaticAccess { return }
    guard pendingRequest == nil else { throw AccessError.requestInProgress }
    let request = Request(id: makeID(), server: server, operation: operation, arguments: arguments)
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        self.continuation = continuation
        pendingRequest = request
      }
      try Task.checkCancellation()
    } onCancel: {
      Task { @MainActor in self.resolve(id: request.id, decision: .cancel) }
    }
  }

  func resolve(id: UUID, decision: Decision) {
    guard pendingRequest?.id == id else { return }
    let suspended = continuation
    continuation = nil
    pendingRequest = nil
    switch decision {
    case .allowOnce:
      suspended?.resume()
    case .alwaysAllow:
      allowsAutomaticAccess = true
      suspended?.resume()
    case .cancel:
      suspended?.resume(throwing: AccessError.denied)
    }
  }

  func cancelPending() {
    guard let id = pendingRequest?.id else { return }
    resolve(id: id, decision: .cancel)
  }

  struct Request: Identifiable {
    var id: UUID
    var server: URL
    var operation: String
    var arguments: String
  }

  enum Decision { case allowOnce, alwaysAllow, cancel }
  enum AccessError: LocalizedError {
    case denied
    case requestInProgress
    var errorDescription: String? {
      switch self {
      case .denied: "MCP access was not allowed. No request was sent to Sure."
      case .requestInProgress: "Another MCP request is waiting for permission."
      }
    }
  }
}

@MainActor
protocol MCPAccessPreferences {
  func allowsAutomaticAccess() -> Bool
  func setAllowsAutomaticAccess(_ allowed: Bool)
}
