import Foundation
import Observation
import WatchConnectivity

@Observable
final class WatchInsightsStore: NSObject, WCSessionDelegate {
  var insights: [WatchInsight] = []
  var lastUpdated: Date?

  private let cachedInsightsKey = "cachedWatchInsights"
  private let lastUpdatedKey = "watchInsightsLastUpdated"

  override init() {
    super.init()
    loadCache()
    activate()
  }

  func session(
    _ session: WCSession,
    activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    receive(session.applicationContext)
  }

  func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
    receive(applicationContext)
  }

  private func activate() {
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    session.delegate = self
    session.activate()
  }

  private func receive(_ context: [String: Any]) {
    guard
      let data = context["insights"] as? Data,
      let decoded = try? JSONDecoder().decode([WatchInsight].self, from: data)
    else { return }

    let updateDate = (context["updatedAt"] as? Double).map(Date.init(timeIntervalSince1970:)) ?? .now
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      insights = decoded
      lastUpdated = updateDate
      saveCache()
    }
  }

  private func loadCache() {
    let defaults = UserDefaults.standard
    if
      let encoded = defaults.string(forKey: cachedInsightsKey),
      let data = encoded.data(using: .utf8),
      let decoded = try? JSONDecoder().decode([WatchInsight].self, from: data)
    {
      insights = decoded
    }
    lastUpdated = defaults.object(forKey: lastUpdatedKey) as? Date
  }

  private func saveCache() {
    guard
      let data = try? JSONEncoder().encode(insights),
      let encoded = String(data: data, encoding: .utf8)
    else { return }

    let defaults = UserDefaults.standard
    defaults.set(encoded, forKey: cachedInsightsKey)
    defaults.set(lastUpdated, forKey: lastUpdatedKey)
  }
}
