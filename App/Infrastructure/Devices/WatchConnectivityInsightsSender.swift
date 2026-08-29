#if os(iOS)
import Foundation
import WatchConnectivity

@MainActor
final class WatchConnectivityInsightsSender: NSObject, WatchInsightsSendingTransport, WCSessionDelegate {
  private let session: WCSession?
  private var stateDidChange: (@MainActor (WatchInsightsSessionState) -> Void)?
  private(set) var sessionState: WatchInsightsSessionState

  override init() {
    if WCSession.isSupported() {
      let session = WCSession.default
      self.session = session
      sessionState = Self.state(for: session.activationState)
    } else {
      session = nil
      sessionState = .unsupported
    }
    super.init()
  }

  func activate(
    stateDidChange: @escaping @MainActor (WatchInsightsSessionState) -> Void
  ) {
    self.stateDidChange = stateDidChange
    guard let session else {
      transition(to: .unsupported)
      return
    }

    session.delegate = self
    if session.activationState == .activated {
      transition(to: .active)
    } else {
      transition(to: .activating)
      session.activate()
    }
  }

  func updateApplicationContext(_ applicationContext: [String: Any]) throws {
    guard let session, session.activationState == .activated else {
      throw WatchInsightsSendingTransportError.inactiveSession
    }
    try session.updateApplicationContext(applicationContext)
  }

  nonisolated func session(
    _ session: WCSession,
    activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    let didFail = error != nil
    Task { @MainActor [weak self] in
      guard let self else { return }
      transition(to: didFail ? .failed : Self.state(for: activationState))
    }
  }

  nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
    Task { @MainActor [weak self] in
      self?.transition(to: .inactive)
    }
  }

  nonisolated func sessionDidDeactivate(_ session: WCSession) {
    Task { @MainActor [weak self] in
      guard let self, let session = self.session else { return }
      transition(to: .activating)
      session.activate()
    }
  }

  private func transition(to state: WatchInsightsSessionState) {
    sessionState = state
    stateDidChange?(state)
  }

  private static func state(for activationState: WCSessionActivationState) -> WatchInsightsSessionState {
    switch activationState {
    case .activated: .active
    case .inactive: .inactive
    case .notActivated: .inactive
    @unknown default: .failed
    }
  }
}

enum WatchInsightsSendingTransportError: Error {
  case inactiveSession
}
#endif
