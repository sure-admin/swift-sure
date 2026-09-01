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

  private let connector: any AppleCardConnecting

  init(connector: any AppleCardConnecting) {
    self.connector = connector
  }

  func refresh() async {
    guard state != .checking && state != .connecting else { return }
    guard connector.isAvailable else {
      state = .unavailable
      return
    }

    state = .checking
    do {
      state = Self.state(for: try await connector.authorizationStatus())
    } catch is CancellationError {
      state = .idle
    } catch {
      state = .failed("Apple Card access is temporarily unavailable.")
    }
  }

  func connect() async {
    guard connector.isAvailable else {
      state = .unavailable
      return
    }

    state = .connecting
    do {
      state = Self.state(for: try await connector.requestAuthorization())
    } catch is CancellationError {
      state = .ready
    } catch {
      state = .failed("Apple Card couldn’t be connected. Please try again.")
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
