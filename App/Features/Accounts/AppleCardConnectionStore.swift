import Foundation
import Observation

@MainActor
@Observable
final class AppleCardConnectionStore: WalletSpendingAccessProviding {
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

  func accounts(excludingSyncedSourceIDs sourceIDs: Set<UUID>) -> [LocalFinancialAccount] {
    accounts.filter { !sourceIDs.contains($0.id) }
  }

  var isAvailable: Bool { connector.isAvailable }
  private var generation = 0

  var walletSpendingAccess: WalletSpendingAccess {
    WalletSpendingAccess(
      isAuthorized: state == .authorized || (state == .checking && !accounts.isEmpty),
      accountIDs: Set(accounts.map(\.id)),
      currencies: Set(accounts.compactMap { $0.balance?.currency }),
      generation: generation
    )
  }

  private let connector: any AppleCardConnecting

  init(connector: any AppleCardConnecting) {
    self.connector = connector
  }

  func refresh() async {
    guard state != .checking && state != .connecting else { return }
    guard connector.isAvailable else {
      accounts = []
      state = .unavailable
      return
    }

    let requestGeneration = generation
    let previousState = state
    state = .checking
    do {
      let authorization = try await connector.authorizationStatus()
      let loadedAccounts = authorization == .authorized ? try await connector.fetchAccounts() : []
      try Task.checkCancellation()
      guard generation == requestGeneration else { return }
      generation += 1
      accounts = loadedAccounts
      state = Self.state(for: authorization)
    } catch is CancellationError {
      guard generation == requestGeneration else { return }
      state = previousState
    } catch {
      guard generation == requestGeneration else { return }
      state = .failed("Wallet accounts couldn’t be refreshed. Previously loaded accounts may be out of date.")
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
      generation += 1
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
