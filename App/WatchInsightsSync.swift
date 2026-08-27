#if os(iOS)
import Foundation
import WatchConnectivity

final class WatchInsightsSync: NSObject, WCSessionDelegate {
  static let shared = WatchInsightsSync()

  private var session: WCSession?

  private override init() {
    super.init()
    activate()
  }

  func activate() {
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    self.session = session
    session.delegate = self
    session.activate()
  }

  func send(_ insights: [BackendInsight]) {
    guard let session else {
      activate()
      return
    }

    let watchInsights = insights.map {
      WatchInsight(
        id: $0.id,
        type: $0.type,
        title: $0.title,
        body: $0.body,
        priority: $0.priority,
        generatedAt: $0.generatedAt
      )
    }

    do {
      let data = try JSONEncoder().encode(watchInsights)
      try session.updateApplicationContext([
        "insights": data,
        "updatedAt": Date.now.timeIntervalSince1970
      ])
    } catch {
      // The next successful refresh will replace the application context.
    }
  }

  func session(
    _ session: WCSession,
    activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) { }

  func sessionDidBecomeInactive(_ session: WCSession) { }

  func sessionDidDeactivate(_ session: WCSession) {
    session.activate()
  }
}
#endif
