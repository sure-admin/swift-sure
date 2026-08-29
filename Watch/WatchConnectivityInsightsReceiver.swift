import Foundation
import WatchConnectivity

@MainActor
final class WatchConnectivityInsightsReceiver: NSObject, WatchInsightsReceiving, WCSessionDelegate {
  private let session: WCSession?
  private let codec: WatchInsightsSnapshotCodec
  private let now: () -> Date
  private var handler: (@MainActor (WatchInsightsReceiverEvent) -> Void)?

  init(
    codec: WatchInsightsSnapshotCodec = WatchInsightsSnapshotCodec(),
    now: @escaping () -> Date
  ) {
    session = WCSession.isSupported() ? .default : nil
    self.codec = codec
    self.now = now
    super.init()
  }

  func activate(handler: @escaping @MainActor (WatchInsightsReceiverEvent) -> Void) {
    self.handler = handler
    guard let session else {
      handler(.stateChanged(.unsupported))
      return
    }

    session.delegate = self
    if session.activationState == .activated {
      handler(.stateChanged(.active))
      receive(session.applicationContext)
    } else {
      handler(.stateChanged(.activating))
      session.activate()
    }
  }

  nonisolated func session(
    _ session: WCSession,
    activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    let applicationContext = session.applicationContext
    let didFail = error != nil
    Task { @MainActor [weak self] in
      guard let self else { return }
      if didFail {
        handler?(.stateChanged(.failed))
        return
      }

      let state: WatchInsightsSessionState = activationState == .activated ? .active : .inactive
      handler?(.stateChanged(state))
      if state == .active {
        receive(applicationContext)
      }
    }
  }

  nonisolated func session(
    _ session: WCSession,
    didReceiveApplicationContext applicationContext: [String: Any]
  ) {
    Task { @MainActor [weak self] in
      self?.receive(applicationContext)
    }
  }

  private func receive(_ applicationContext: [String: Any]) {
    do {
      let snapshot = try codec.snapshot(from: applicationContext, now: now)
      handler?(.snapshot(.success(snapshot)))
    } catch let error as WatchInsightsSnapshotCodingError {
      handler?(.snapshot(.failure(error)))
    } catch {
      handler?(.snapshot(.failure(.malformedPayload)))
    }
  }
}
