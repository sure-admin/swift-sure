import Foundation
import Testing
@testable import Sure_Watch

@Suite("Watch insights cache")
struct UserDefaultsWatchInsightsCacheTests {
  @Test("Snapshot data round-trips through an isolated preferences store")
  func roundTrip() throws {
    let suiteName = "SureWatchTests.WatchInsightsCache.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let cache = UserDefaultsWatchInsightsCache(defaults: defaults)
    let expected = Data("snapshot".utf8)

    try cache.saveSnapshotData(expected)

    #expect(try cache.loadSnapshotData() == expected)
  }

  @Test("A valid legacy cache migrates into the typed snapshot shape")
  func legacyMigration() throws {
    let suiteName = "SureWatchTests.WatchInsightsLegacy.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let insight = WatchInsight(
      id: "insight-1",
      type: "spending",
      title: "Spending changed",
      body: "Review the latest activity.",
      priority: "high",
      generatedAt: nil
    )
    let updatedAt = Date(timeIntervalSince1970: 1_800_000_000)
    let legacyData = try JSONEncoder().encode([insight])
    defaults.set(String(decoding: legacyData, as: UTF8.self), forKey: "cachedWatchInsights")
    defaults.set(updatedAt, forKey: "watchInsightsLastUpdated")
    let cache = UserDefaultsWatchInsightsCache(defaults: defaults)

    let loadedData = try cache.loadSnapshotData()
    let migratedData = try #require(loadedData)
    let migrated = try WatchInsightsSnapshotCodec().decode(migratedData)

    #expect(migrated == WatchInsightsSnapshot(insights: [insight], updatedAt: updatedAt))
  }
}
