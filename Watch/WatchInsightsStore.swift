import Foundation
import Observation

@MainActor
@Observable
final class WatchInsightsStore {
  private(set) var insights: [WatchInsight] = []
  private(set) var lastUpdated: Date?
  private(set) var sessionState: WatchInsightsSessionState = .inactive

  private let receiver: any WatchInsightsReceiving
  private let cache: any WatchInsightsCaching
  private let codec: WatchInsightsSnapshotCodec
  private var hasStarted = false

  init(
    receiver: any WatchInsightsReceiving,
    cache: any WatchInsightsCaching,
    codec: WatchInsightsSnapshotCodec = WatchInsightsSnapshotCodec()
  ) {
    self.receiver = receiver
    self.cache = cache
    self.codec = codec
    loadCache()
  }

  func start() {
    guard !hasStarted else { return }
    hasStarted = true
    sessionState = .activating
    receiver.activate { [weak self] event in
      self?.handle(event)
    }
  }

  private func handle(_ event: WatchInsightsReceiverEvent) {
    switch event {
    case .stateChanged(let state):
      sessionState = state
    case .snapshot(.success(let snapshot)):
      apply(snapshot)
    case .snapshot(.failure):
      break
    }
  }

  private func apply(_ snapshot: WatchInsightsSnapshot) {
    guard lastUpdated.map({ snapshot.updatedAt >= $0 }) ?? true else { return }
    insights = snapshot.insights
    lastUpdated = snapshot.updatedAt
    guard let data = try? codec.encode(snapshot) else { return }
    try? cache.saveSnapshotData(data)
  }

  private func loadCache() {
    guard
      let data = try? cache.loadSnapshotData(),
      let snapshot = try? codec.decode(data)
    else {
      return
    }

    insights = snapshot.insights
    lastUpdated = snapshot.updatedAt
  }
}
