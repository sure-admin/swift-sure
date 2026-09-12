import Foundation

/// One gate for every Sure network operation, including authentication and uploads.
final class BackendAccessGate: @unchecked Sendable {
  private let lock = NSLock()
  private var expiration: Date?
  private var generation = 0
  private var cancellations: [UUID: @Sendable () -> Void] = [:]
  private let now: @Sendable () -> Date

  init(now: @escaping @Sendable () -> Date = { Date() }) { self.now = now }

  var isAllowed: Bool { lock.withLock { expiration.map { $0 > now() } ?? false } }

  func update(expiration: Date?) {
    let callbacks = lock.withLock {
      self.expiration = expiration
      guard expiration.map({ $0 > now() }) != true else { return [@Sendable () -> Void]() }
      generation += 1
      let result = Array(cancellations.values)
      cancellations.removeAll()
      return result
    }
    callbacks.forEach { $0() }
  }

  func check() throws {
    guard isAllowed else { throw BackendAccessError.subscriptionRequired }
  }

  func permit() throws -> Int {
    try lock.withLock {
      guard expiration.map({ $0 > now() }) == true else { throw BackendAccessError.subscriptionRequired }
      return generation
    }
  }

  func validate(_ permit: Int) throws {
    try lock.withLock {
      guard generation == permit, expiration.map({ $0 > now() }) == true else {
        throw BackendAccessError.subscriptionRequired
      }
    }
  }

  func register(_ id: UUID, permit: Int, cancel: @escaping @Sendable () -> Void) throws {
    try lock.withLock {
      guard generation == permit, expiration.map({ $0 > now() }) == true else {
        throw BackendAccessError.subscriptionRequired
      }
      cancellations[id] = cancel
    }
  }

  func unregister(_ id: UUID) { lock.withLock { _ = cancellations.removeValue(forKey: id) } }
}

enum BackendAccessError: LocalizedError {
  case subscriptionRequired
  var errorDescription: String? {
    String(localized: "Sync is paused. Start or restore a subscription to connect to Sure. Downloaded data and local features remain available.")
  }
}
