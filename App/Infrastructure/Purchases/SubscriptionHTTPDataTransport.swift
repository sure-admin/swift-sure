import Foundation

struct SubscriptionHTTPDataTransport: HTTPDataTransport {
  var base: any HTTPDataTransport
  var gate: BackendAccessGate

  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    let permit = try gate.permit()
    let id = UUID()
    let task = Task {
      try gate.validate(permit)
      return try await base.data(for: request)
    }
    do { try gate.register(id, permit: permit, cancel: { task.cancel() }) }
    catch { task.cancel(); throw error }
    defer { gate.unregister(id) }
    return try await withTaskCancellationHandler {
      let result = try await task.value
      try Task.checkCancellation()
      try gate.validate(permit)
      return result
    } onCancel: { task.cancel() }
  }
}
