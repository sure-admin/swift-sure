import Foundation

struct WatchInsightsSnapshotCodec {
  private enum Key {
    static var snapshot = "watchInsightsSnapshot"
    static var legacyInsights = "insights"
    static var legacyUpdatedAt = "updatedAt"
  }

  private var encoder: JSONEncoder
  private var decoder: JSONDecoder

  init(
    encoder: JSONEncoder = JSONEncoder(),
    decoder: JSONDecoder = JSONDecoder()
  ) {
    self.encoder = encoder
    self.decoder = decoder
  }

  func encode(_ snapshot: WatchInsightsSnapshot) throws -> Data {
    do {
      return try encoder.encode(snapshot)
    } catch {
      throw WatchInsightsSnapshotCodingError.malformedPayload
    }
  }

  func decode(_ data: Data) throws -> WatchInsightsSnapshot {
    do {
      return try decoder.decode(WatchInsightsSnapshot.self, from: data)
    } catch {
      throw WatchInsightsSnapshotCodingError.malformedPayload
    }
  }

  func applicationContext(for snapshot: WatchInsightsSnapshot) throws -> [String: Any] {
    let snapshotData = try encode(snapshot)
    let legacyInsightsData: Data
    do {
      legacyInsightsData = try encoder.encode(snapshot.insights)
    } catch {
      throw WatchInsightsSnapshotCodingError.malformedPayload
    }

    // Keep the legacy fields during the TestFlight phase so independently
    // updated phone and Watch builds continue to exchange the latest snapshot.
    return [
      Key.snapshot: snapshotData,
      Key.legacyInsights: legacyInsightsData,
      Key.legacyUpdatedAt: snapshot.updatedAt.timeIntervalSince1970
    ]
  }

  func snapshot(
    from applicationContext: [String: Any],
    now: () -> Date
  ) throws -> WatchInsightsSnapshot {
    if let data = applicationContext[Key.snapshot] as? Data {
      return try decode(data)
    }

    guard let data = applicationContext[Key.legacyInsights] as? Data else {
      throw WatchInsightsSnapshotCodingError.missingPayload
    }

    let insights: [WatchInsight]
    do {
      insights = try decoder.decode([WatchInsight].self, from: data)
    } catch {
      throw WatchInsightsSnapshotCodingError.malformedPayload
    }

    let updatedAt = (applicationContext[Key.legacyUpdatedAt] as? Double)
      .map(Date.init(timeIntervalSince1970:)) ?? now()
    return WatchInsightsSnapshot(insights: insights, updatedAt: updatedAt)
  }
}

enum WatchInsightsSnapshotCodingError: Error, Equatable {
  case missingPayload
  case malformedPayload
}
