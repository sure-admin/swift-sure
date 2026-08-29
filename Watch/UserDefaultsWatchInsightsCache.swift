import Foundation

struct UserDefaultsWatchInsightsCache: WatchInsightsCaching {
  private enum Key {
    static var snapshot = "watchInsightsSnapshot.v1"
    static var legacyInsights = "cachedWatchInsights"
    static var legacyUpdatedAt = "watchInsightsLastUpdated"
  }

  private var defaults: UserDefaults
  private var codec: WatchInsightsSnapshotCodec

  init(
    defaults: UserDefaults,
    codec: WatchInsightsSnapshotCodec = WatchInsightsSnapshotCodec()
  ) {
    self.defaults = defaults
    self.codec = codec
  }

  func loadSnapshotData() throws -> Data? {
    if let data = defaults.data(forKey: Key.snapshot) {
      return data
    }

    guard
      let encodedInsights = defaults.string(forKey: Key.legacyInsights),
      let insightsData = encodedInsights.data(using: .utf8),
      let insights = try? JSONDecoder().decode([WatchInsight].self, from: insightsData),
      let updatedAt = defaults.object(forKey: Key.legacyUpdatedAt) as? Date
    else {
      return nil
    }

    return try codec.encode(
      WatchInsightsSnapshot(insights: insights, updatedAt: updatedAt)
    )
  }

  func saveSnapshotData(_ data: Data) throws {
    defaults.set(data, forKey: Key.snapshot)
  }
}
