import Foundation
import Observation

@MainActor
@Observable
final class AppleCardConnectionStore {
  enum State: Equatable {
    case idle
    case checking
    case ready
    case connecting
    case authorized
    case denied
    case unavailable
    case failed(String)
  }

  private(set) var state: State = .idle
  private(set) var accounts: [LocalFinancialAccount] = []

  var isAvailable: Bool { connector.isAvailable }
  private var generation = 0

  // Logout clears app-owned data without changing system Wallet permission.
  func disconnect() {
    generation += 1
    requiresReconnect = true
    setRequiresReconnect(true)
    accounts = []
    state = connector.isAvailable ? .ready : .unavailable
  }

  private let connector: any AppleCardConnecting

  private var requiresReconnect: Bool
  private let setRequiresReconnect: (Bool) -> Void

  init(
    connector: any AppleCardConnecting,
    requiresReconnect: Bool = false,
    setRequiresReconnect: @escaping (Bool) -> Void = { _ in }
  ) {
    self.requiresReconnect = requiresReconnect
    self.connector = connector
    self.setRequiresReconnect = setRequiresReconnect
    if requiresReconnect {
      state = connector.isAvailable ? .ready : .unavailable
    }
  }

  func refresh() async {
    guard !requiresReconnect else { return }
    guard state != .checking && state != .connecting else { return }
    guard connector.isAvailable else {
      accounts = []
      state = .unavailable
      return
    }

    let requestGeneration = generation
    state = .checking
    do {
      let authorization = try await connector.authorizationStatus()
      let loadedAccounts = authorization == .authorized ? try await connector.fetchAccounts() : []
      try Task.checkCancellation()
      guard generation == requestGeneration else { return }
      accounts = loadedAccounts
      state = Self.state(for: authorization)
    } catch is CancellationError {
      guard generation == requestGeneration else { return }
      state = .idle
    } catch {
      guard generation == requestGeneration else { return }
      accounts = []
      state = .failed("Wallet accounts are temporarily unavailable.")
    }
  }

  func connect() async {
    guard connector.isAvailable else {
      accounts = []
      state = .unavailable
      return
    }

    guard state != .checking && state != .connecting else { return }
    let requestGeneration = generation
    state = .connecting
    do {
      let authorization = try await connector.requestAuthorization()
      let loadedAccounts = authorization == .authorized ? try await connector.fetchAccounts() : []
      try Task.checkCancellation()
      guard generation == requestGeneration else { return }
      if authorization == .authorized {
        requiresReconnect = false
        setRequiresReconnect(false)
      }
      accounts = loadedAccounts
      state = Self.state(for: authorization)
    } catch is CancellationError {
      guard generation == requestGeneration else { return }
      state = .ready
    } catch {
      guard generation == requestGeneration else { return }
      accounts = []
      state = .failed("Wallet accounts couldn’t be loaded. Please try again.")
    }
  }

  private static func state(for authorization: AppleCardAuthorization) -> State {
    switch authorization {
    case .notDetermined: .ready
    case .authorized: .authorized
    case .denied: .denied
    }
  }
}
