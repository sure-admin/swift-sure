#if os(iOS)
import Foundation

@MainActor
final class WatchInsightsSync {
  private let transport: any WatchInsightsSendingTransport
  private let codec: WatchInsightsSnapshotCodec
  private let now: () -> Date
  private let nextRevision: () -> (String, UInt64)?
  private var pendingSnapshot: WatchInsightsSnapshot?
  private var hasActivated = false

  init(
    transport: any WatchInsightsSendingTransport,
    codec: WatchInsightsSnapshotCodec = WatchInsightsSnapshotCodec(),
    now: @escaping () -> Date,
    nextRevision: @escaping () -> (String, UInt64)? = { nil }
  ) {
    self.transport = transport
    self.codec = codec
    self.now = now
    self.nextRevision = nextRevision
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
    let sequence = nextRevision()
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
      updatedAt: now(),
      streamID: sequence?.0, revision: sequence?.1
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
