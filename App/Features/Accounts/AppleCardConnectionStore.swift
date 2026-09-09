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

    state = .checking
    do {
      let authorization = try await connector.authorizationStatus()
      state = Self.state(for: authorization)
      if authorization == .authorized {
        accounts = try await connector.fetchAccounts()
      } else {
        accounts = []
      }
    } catch is CancellationError {
      state = .idle
    } catch {
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

    state = .connecting
    do {
      let authorization = try await connector.requestAuthorization()
      state = Self.state(for: authorization)
      if authorization == .authorized {
        accounts = try await connector.fetchAccounts()
      } else {
        accounts = []
      }
    } catch is CancellationError {
      state = .ready
    } catch {
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
