#if os(iOS)
import Foundation
import Testing
@testable import Sure

@MainActor
@Suite("Watch insights sync")
struct WatchInsightsSyncTests {
  @Test("The latest snapshot waits for an active session")
  func waitsForActiveSession() throws {
    let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)
    let transport = WatchInsightsSendingTransportFake(state: .inactive)
    let sync = WatchInsightsSync(transport: transport, now: { fixedNow })

    sync.send([insight(id: "first")])
    sync.send([insight(id: "latest")])

    #expect(transport.activationCount == 1)
    #expect(transport.applicationContexts.isEmpty)

    transport.transition(to: .active)

    let context = try #require(transport.applicationContexts.first)
    let snapshot = try WatchInsightsSnapshotCodec().snapshot(
      from: context,
      now: { .distantPast }
    )
    #expect(snapshot.insights.map(\.id) == ["latest"])
    #expect(snapshot.updatedAt == fixedNow)
  }

  @Test("An active session receives each replacement context immediately")
  func activeSession() {
    let transport = WatchInsightsSendingTransportFake(state: .active)
    let sync = WatchInsightsSync(transport: transport, now: { .distantPast })

    sync.activate()
    sync.send([insight(id: "one")])
    sync.send([insight(id: "two")])

    #expect(transport.applicationContexts.count == 2)
  }

  @Test("Every typed insight field crosses the phone-to-watch boundary")
  func mapsCompleteInsight() throws {
    let generatedAt = Date(timeIntervalSince1970: 1_799_999_000)
    let updatedAt = Date(timeIntervalSince1970: 1_800_000_000)
    let transport = WatchInsightsSendingTransportFake(state: .active)
    let sync = WatchInsightsSync(transport: transport, now: { updatedAt })
    let source = BackendInsight(
      id: "insight-1",
      type: "spending",
      title: "Spending changed",
      body: "Review the latest activity.",
      priority: "high",
      status: "active",
      generatedAt: generatedAt
    )

    sync.send([source])

    let context = try #require(transport.applicationContexts.first)
    let snapshot = try WatchInsightsSnapshotCodec().snapshot(from: context, now: { .distantPast })
    let received = try #require(snapshot.insights.first)
    #expect(received.id == source.id)
    #expect(received.type == source.type)
    #expect(received.title == source.title)
    #expect(received.body == source.body)
    #expect(received.priority == source.priority)
    #expect(received.generatedAt == source.generatedAt)
    #expect(snapshot.updatedAt == updatedAt)
  }

  @Test("A failed send retains the snapshot for the next active transition")
  func retryAfterSendFailure() throws {
    let transport = WatchInsightsSendingTransportFake(
      state: .active,
      sendError: WatchInsightsSyncTestError.expected
    )
    let sync = WatchInsightsSync(transport: transport, now: { .distantPast })

    sync.activate()
    sync.send([insight(id: "retry")])
    #expect(transport.applicationContexts.isEmpty)

    transport.sendError = nil
    transport.transition(to: .inactive)
    transport.transition(to: .active)

    let context = try #require(transport.applicationContexts.first)
    let snapshot = try WatchInsightsSnapshotCodec().snapshot(
      from: context,
      now: { .now }
    )
    #expect(snapshot.insights.map(\.id) == ["retry"])
  }

  private func insight(id: String) -> BackendInsight {
    BackendInsight(
      id: id,
      type: "budget",
      title: "On track",
      body: "Spending is within the plan.",
      priority: "medium",
      status: "active",
      generatedAt: nil
    )
  }
}

@MainActor
private final class WatchInsightsSendingTransportFake: WatchInsightsSendingTransport {
  private var stateDidChange: (@MainActor (WatchInsightsSessionState) -> Void)?
  private(set) var sessionState: WatchInsightsSessionState
  private(set) var activationCount = 0
  private(set) var applicationContexts: [[String: Any]] = []
  var sendError: Error?

  init(state: WatchInsightsSessionState, sendError: Error? = nil) {
    sessionState = state
    self.sendError = sendError
  }

  func activate(
    stateDidChange: @escaping @MainActor (WatchInsightsSessionState) -> Void
  ) {
    activationCount += 1
    self.stateDidChange = stateDidChange
    stateDidChange(sessionState)
  }

  func updateApplicationContext(_ applicationContext: [String: Any]) throws {
    if let sendError { throw sendError }
    applicationContexts.append(applicationContext)
  }

  func transition(to state: WatchInsightsSessionState) {
    sessionState = state
    stateDidChange?(state)
  }
}

private enum WatchInsightsSyncTestError: Error {
  case expected
}
#endif
