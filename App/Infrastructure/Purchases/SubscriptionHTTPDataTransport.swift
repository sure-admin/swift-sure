import Foundation

struct SubscriptionHTTPDataTransport: HTTPDataTransport {
  var base: any HTTPDataTransport
  var gate: BackendAccessGate

  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    let permit = try gate.permit()
    let id = UUID()
    let cancellation = SubscriptionRequestCancellation()
    try gate.register(id, permit: permit, cancel: { cancellation.cancel() })
    defer { gate.unregister(id) }
    let task = Task {
      try Task.checkCancellation()
      try gate.validate(permit)
      return try await base.data(for: request)
    }
    cancellation.install { task.cancel() }
    return try await withTaskCancellationHandler {
      let result = try await task.value
      try Task.checkCancellation()
      try gate.validate(permit)
      return result
    } onCancel: { cancellation.cancel() }
  }
}

// Revocation can happen before the request task exists. Remember it so installing
// the task's cancellation action cannot lose that notification.
final class SubscriptionRequestCancellation: @unchecked Sendable {
  private let lock = NSLock()
  private var isCancelled = false
  private var action: (@Sendable () -> Void)?

  func install(_ action: @escaping @Sendable () -> Void) {
    let shouldCancel = lock.withLock {
      if isCancelled { return true }
      self.action = action
      return false
    }
    if shouldCancel { action() }
  }

  func cancel() {
    let action = lock.withLock {
      isCancelled = true
      let action = self.action
      self.action = nil
      return action
    }
    action?()
  }
}
