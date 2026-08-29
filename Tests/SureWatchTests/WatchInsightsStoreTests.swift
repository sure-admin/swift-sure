import Foundation
import Testing
@testable import Sure_Watch

@MainActor
@Suite("Watch insights store")
struct WatchInsightsStoreTests {
  @Test("A valid cached snapshot is restored at launch")
  func restoresCache() throws {
    let expected = snapshot()
    let cache = WatchInsightsCacheFake(
      loadedData: try WatchInsightsSnapshotCodec().encode(expected)
    )

    let store = WatchInsightsStore(
      receiver: WatchInsightsReceiverFake(),
      cache: cache
    )

    #expect(store.insights == expected.insights)
    #expect(store.lastUpdated == expected.updatedAt)
  }

  @Test("A malformed or unavailable cache leaves explicit empty state")
  func invalidCache() {
    let malformedStore = WatchInsightsStore(
      receiver: WatchInsightsReceiverFake(),
      cache: WatchInsightsCacheFake(loadedData: Data("invalid".utf8))
    )
    let failedStore = WatchInsightsStore(
      receiver: WatchInsightsReceiverFake(),
      cache: WatchInsightsCacheFake(loadError: WatchInsightsTestError.expected)
    )

    #expect(malformedStore.insights.isEmpty)
    #expect(malformedStore.lastUpdated == nil)
    #expect(failedStore.insights.isEmpty)
    #expect(failedStore.lastUpdated == nil)
  }

  @Test("A received snapshot updates state and cache")
  func receivesSnapshot() throws {
    let receiver = WatchInsightsReceiverFake()
    let cache = WatchInsightsCacheFake()
    let store = WatchInsightsStore(receiver: receiver, cache: cache)
    let expected = snapshot()

    store.start()
    receiver.emit(.snapshot(.success(expected)))

    #expect(store.insights == expected.insights)
    #expect(store.lastUpdated == expected.updatedAt)
    let savedData = try #require(cache.savedData)
    #expect(try WatchInsightsSnapshotCodec().decode(savedData) == expected)
  }

  @Test("Decode and cache-write failures do not erase a received snapshot")
  func receiveFailures() {
    let receiver = WatchInsightsReceiverFake()
    let cache = WatchInsightsCacheFake(saveError: WatchInsightsTestError.expected)
    let store = WatchInsightsStore(receiver: receiver, cache: cache)
    let expected = snapshot()

    store.start()
    receiver.emit(.snapshot(.success(expected)))
    receiver.emit(.snapshot(.failure(.malformedPayload)))

    #expect(store.insights == expected.insights)
    #expect(store.lastUpdated == expected.updatedAt)
    #expect(cache.saveCount == 1)
  }

  @Test("An older financial snapshot cannot replace a newer logout clearing snapshot")
  func ignoresOlderSnapshot() {
    let receiver = WatchInsightsReceiverFake()
    let cache = WatchInsightsCacheFake()
    let store = WatchInsightsStore(receiver: receiver, cache: cache)
    let financial = snapshot()
    let newerClearingSnapshot = WatchInsightsSnapshot(
      insights: [],
      updatedAt: financial.updatedAt.addingTimeInterval(1)
    )
    let older = WatchInsightsSnapshot(
      insights: financial.insights,
      updatedAt: financial.updatedAt
    )

    store.start()
    receiver.emit(.snapshot(.success(newerClearingSnapshot)))
    receiver.emit(.snapshot(.success(older)))

    #expect(store.insights.isEmpty)
    #expect(store.lastUpdated == newerClearingSnapshot.updatedAt)
    #expect(cache.saveCount == 1)
  }

  @Test("Session state is observable and activation is idempotent")
  func sessionState() {
    let receiver = WatchInsightsReceiverFake()
    let store = WatchInsightsStore(
      receiver: receiver,
      cache: WatchInsightsCacheFake()
    )

    store.start()
    store.start()
    #expect(store.sessionState == .activating)
    #expect(receiver.activationCount == 1)

    receiver.emit(.stateChanged(.active))
    #expect(store.sessionState == .active)

    receiver.emit(.stateChanged(.failed))
    #expect(store.sessionState == .failed)
  }

  private func snapshot() -> WatchInsightsSnapshot {
    WatchInsightsSnapshot(
      insights: [
        WatchInsight(
          id: "insight-1",
          type: "spending",
          title: "Spending changed",
          body: "Review the latest activity.",
          priority: "high",
          generatedAt: nil
        )
      ],
      updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
    )
  }
}

@MainActor
private final class WatchInsightsReceiverFake: WatchInsightsReceiving {
  private var handler: (@MainActor (WatchInsightsReceiverEvent) -> Void)?
  private(set) var activationCount = 0

  func activate(handler: @escaping @MainActor (WatchInsightsReceiverEvent) -> Void) {
    activationCount += 1
    self.handler = handler
  }

  func emit(_ event: WatchInsightsReceiverEvent) {
    handler?(event)
  }
}

private final class WatchInsightsCacheFake: WatchInsightsCaching {
  private var loadedData: Data?
  private var loadError: Error?
  private var saveError: Error?
  private(set) var savedData: Data?
  private(set) var saveCount = 0

  init(
    loadedData: Data? = nil,
    loadError: Error? = nil,
    saveError: Error? = nil
  ) {
    self.loadedData = loadedData
    self.loadError = loadError
    self.saveError = saveError
  }

  func loadSnapshotData() throws -> Data? {
    if let loadError { throw loadError }
    return loadedData
  }

  func saveSnapshotData(_ data: Data) throws {
    saveCount += 1
    if let saveError { throw saveError }
    savedData = data
  }
}

private enum WatchInsightsTestError: Error {
  case expected
}
