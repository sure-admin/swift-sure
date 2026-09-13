import Foundation
import Observation

@MainActor
@Observable
final class FinanceResource<Value> {
  var value: Value
  private(set) var hasValue = false
  private(set) var isLoading = false
  private(set) var failure: DataFailure?
  private(set) var metadata: ReadMetadata?
  private let empty: Value
  private var generation = 0

  init(_ empty: Value) { value = empty; self.empty = empty }

  func load(now: () -> Date, metadata: () async -> ReadMetadata?,
            operation: () async throws -> Value) async -> Bool {
    guard !Task.isCancelled else { return false }
    generation &+= 1
    let request = generation
    isLoading = true
    defer { if request == generation { isLoading = false } }
    do {
      let loaded = try await operation()
      let info = await metadata() ?? ReadMetadata(fetchedAt: now(), source: .server)
      try Task.checkCancellation()
      guard request == generation else { return false }
      value = loaded; hasValue = true; self.metadata = info; failure = info.failure
      return info.source == .server
    } catch {
      guard request == generation else { return false }
      let error = DataFailure(error)
      if error != .cancelled { failure = error }
      return false
    }
  }

  func restore(_ value: Value, metadata: ReadMetadata?) {
    guard !hasValue else { return }
    self.value = value; self.metadata = metadata; hasValue = true
  }

  func suspend() { generation &+= 1; isLoading = false }
  func clear() { suspend(); value = empty; hasValue = false; failure = nil; metadata = nil }
}
