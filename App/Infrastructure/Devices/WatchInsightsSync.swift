#if os(iOS)
import Foundation

@MainActor
final class WatchInsightsSync {
  private let transport: any WatchInsightsSendingTransport
  private let codec: WatchInsightsSnapshotCodec
  private let now: () -> Date
  private var pendingSnapshot: WatchInsightsSnapshot?
  private var hasActivated = false

  init(
    transport: any WatchInsightsSendingTransport,
    codec: WatchInsightsSnapshotCodec = WatchInsightsSnapshotCodec(),
    now: @escaping () -> Date
  ) {
    self.transport = transport
    self.codec = codec
    self.now = now
  }

  func activate() {
    guard !hasActivated else { return }
    hasActivated = true
    transport.activate { [weak self] state in
      guard state == .active else { return }
      self?.flushPendingSnapshot()
    }
  }

  func send(_ insights: [BackendInsight]) {
    pendingSnapshot = WatchInsightsSnapshot(
      insights: insights.map {
        WatchInsight(
          id: $0.id,
          type: $0.type,
          title: $0.title,
          body: $0.body,
          priority: $0.priority,
          generatedAt: $0.generatedAt
        )
      },
      updatedAt: now()
    )

    activate()
    flushPendingSnapshot()
  }

  private func flushPendingSnapshot() {
    guard
      transport.sessionState == .active,
      let pendingSnapshot,
      let applicationContext = try? codec.applicationContext(for: pendingSnapshot)
    else {
      return
    }

    do {
      try transport.updateApplicationContext(applicationContext)
      self.pendingSnapshot = nil
    } catch {
      // A later state transition or finance refresh will retry the latest snapshot.
    }
  }
}
#endif
