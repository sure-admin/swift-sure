import Foundation
import Testing
@testable import Sure

@MainActor
@Suite("First-run launch hero")
struct FirstRunStoreTests {
  @Test("A device with Wallet opens on its own spending, otherwise on the demo")
  func pageOrder() {
    #expect(makeStore(walletAvailable: true).pages.map(\.kind) == [.wallet, .demo])
    #expect(makeStore(walletAvailable: false).pages.map(\.kind) == [.demo, .wallet])
  }

  @Test("Without Wallet, the Wallet pitch explains itself and opens the demo")
  func unavailableWalletPitch() throws {
    let store = makeStore(walletAvailable: false)
    let wallet = try #require(store.pages.first { $0.kind == .wallet })
    #expect(wallet.action == .exploreDemo)
    #expect(wallet.callToAction == store.copy.walletUnavailable.callToAction)
    #expect(wallet.footnote == store.copy.walletUnavailableFootnote)
  }

  @Test("Flips to the second pitch once after the configured delay")
  func autoAdvance() async {
    var requested: [Duration] = []
    let store = makeStore(sleep: { requested.append($0) })
    await store.runAutoAdvance()
    #expect(store.selectedIndex == 1)
    #expect(requested == [.seconds(5)])
    #expect(!store.hasInteracted)

    await store.runAutoAdvance()
    #expect(store.selectedIndex == 1)
  }

  @Test("A swipe before the delay cancels the automatic flip")
  func interactionStopsAutoAdvance() async {
    let store = makeStore()
    store.select(0)
    await store.runAutoAdvance()
    #expect(store.selectedIndex == 0)
    #expect(store.hasInteracted)
  }

  @Test("A cancelled delay leaves the first pitch showing")
  func cancelledAutoAdvance() async {
    let store = makeStore(sleep: { _ in throw CancellationError() })
    await store.runAutoAdvance()
    #expect(store.selectedIndex == 0)
  }

  @Test("Out-of-range selections are ignored")
  func invalidSelection() {
    let store = makeStore()
    store.select(5)
    store.select(-1)
    #expect(store.selectedIndex == 0)
  }

  @Test("Granting Wallet access finishes on the Wallet outcome and records completion")
  func walletGranted() async throws {
    var completions = 0
    let store = makeStore(connectWallet: { true }, markCompleted: { completions += 1 })
    await store.start(try #require(store.pages.first))
    #expect(store.outcome == .walletConnected)
    #expect(store.isFinished)
    #expect(completions == 1)
  }

  @Test("Declining Wallet access falls back to the demo pitch without finishing")
  func walletDeclined() async throws {
    var completions = 0
    let store = makeStore(connectWallet: { false }, markCompleted: { completions += 1 })
    await store.start(try #require(store.pages.first))
    #expect(store.phase == .pitching)
    #expect(store.walletDeclined)
    #expect(store.selectedPage.kind == .demo)
    #expect(completions == 0)
  }

  @Test("Wallet is not requested twice while the system sheet is open")
  func walletRequestIsSingleFlight() async throws {
    var requests = 0
    var resume: CheckedContinuation<Bool, Never>?
    let store = makeStore(connectWallet: {
      requests += 1
      return await withCheckedContinuation { resume = $0 }
    })
    let pitch = try #require(store.pages.first)
    let first = Task { await store.start(pitch) }
    while resume == nil { await Task.yield() }
    #expect(store.isBusy)
    await store.start(pitch)
    store.select(1)
    #expect(store.selectedIndex == 0)
    resume?.resume(returning: true)
    await first.value
    #expect(requests == 1)
    #expect(store.outcome == .walletConnected)
  }

  @Test("Choosing the demo finishes on the demo outcome")
  func demoChosen() async throws {
    var completions = 0
    let store = makeStore(walletAvailable: false, markCompleted: { completions += 1 })
    await store.start(try #require(store.pages.first))
    #expect(store.outcome == .exploreDemo)
    #expect(completions == 1)
  }

  @Test("Welcome exposure and actions use only fixed variant and pitch values")
  func welcomeAnalytics() async throws {
    let analytics = FirstRunAnalyticsSpy()
    let store = makeStore(analytics: analytics)
    #expect(analytics.events == [.welcomePageViewed(variant: .instantReveal, pitch: .wallet)])

    store.select(1)
    await store.start(try #require(store.pages.first { $0.kind == .demo }))
    #expect(analytics.events == [
      .welcomePageViewed(variant: .instantReveal, pitch: .wallet),
      .welcomePageViewed(variant: .instantReveal, pitch: .demo),
      .welcomeAction(variant: .instantReveal, pitch: .demo, action: .exploreDemo)
    ])
  }

  @Test("Wallet refusal and later acceptance are separate welcome outcomes")
  func walletOutcomes() async throws {
    let analytics = FirstRunAnalyticsSpy()
    var approved = false
    let store = makeStore(connectWallet: { approved }, analytics: analytics)
    let wallet = try #require(store.pages.first { $0.kind == .wallet })
    await store.start(wallet)
    #expect(analytics.events.contains(.welcomeOutcome(variant: .instantReveal, outcome: .walletDeclined)))
    approved = true
    await store.start(wallet)
    #expect(analytics.events.contains(.welcomeOutcome(variant: .instantReveal, outcome: .walletConnected)))
  }

  @Test("Switching variant or region replaces copy without moving the page")
  func applyDesignOptions() {
    let store = makeStore()
    store.select(1)
    store.apply(variant: .heroOverview, region: .unitedKingdom)
    #expect(store.configuration.variant == .heroOverview)
    #expect(store.configuration.region == .unitedKingdom)
    #expect(store.copy == FirstRunCopy.make(variant: .heroOverview, market: .standard, currentMonth: "September"))
    #expect(store.selectedIndex == 1)
  }

  private func makeStore(
    walletAvailable: Bool = true,
    connectWallet: @escaping () async -> Bool = { true },
    markCompleted: @escaping () -> Void = {},
    analytics: (any UsageAnalytics)? = nil,
    sleep: @escaping (Duration) async throws -> Void = { _ in }
  ) -> FirstRunStore {
    FirstRunStore(
      configuration: FirstRunConfiguration(
        variant: .instantReveal, region: .unitedStates, currentMonth: "September", previousMonth: "August"
      ),
      walletAvailable: walletAvailable,
      connectWallet: connectWallet,
      markCompleted: markCompleted,
      analytics: analytics,
      sleep: sleep
    )
  }
}

@MainActor
private final class FirstRunAnalyticsSpy: UsageAnalytics {
  var events: [UsageEvent] = []
  func capture(_ event: UsageEvent) { events.append(event) }
  func resetIdentity() {}
}
