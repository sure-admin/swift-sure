import Foundation
import Observation

/// Launch-hero state: which pitch is showing, the one-time automatic flip,
/// and what happens when a pitch's button is tapped.
@MainActor
@Observable
final class FirstRunStore {
  enum Phase: Equatable {
    case pitching
    case requestingWallet
    case finished(Outcome)
  }

  enum Outcome: Equatable {
    /// Wallet access was granted; land where the local spending preview shows.
    case walletConnected
    /// The person chose the live demo.
    case exploreDemo
  }

  private(set) var configuration: FirstRunConfiguration
  private(set) var copy: FirstRunCopy
  private(set) var market: FirstRunMarket
  private(set) var pages: [FirstRunPitch]
  private(set) var selectedIndex = 0
  private(set) var phase = Phase.pitching
  /// Set once the person swipes or taps a page control; stops the auto-flip.
  private(set) var hasInteracted = false
  /// The system Wallet sheet was dismissed without sharing.
  private(set) var walletDeclined = false

  let walletAvailable: Bool
  private let connectWallet: () async -> Bool
  private let markCompleted: () -> Void
  private let sleep: (Duration) async throws -> Void
  private let analytics: (any UsageAnalytics)?

  init(
    configuration: FirstRunConfiguration,
    walletAvailable: Bool,
    connectWallet: @escaping () async -> Bool,
    markCompleted: @escaping () -> Void,
    analytics: (any UsageAnalytics)? = nil,
    sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
  ) {
    self.configuration = configuration
    self.walletAvailable = walletAvailable
    self.connectWallet = connectWallet
    self.markCompleted = markCompleted
    self.sleep = sleep
    self.analytics = analytics
    let market = FirstRunMarket.market(for: configuration.region)
    let copy = FirstRunCopy.make(variant: configuration.variant, market: market, currentMonth: configuration.currentMonth)
    self.market = market
    self.copy = copy
    pages = Self.pages(copy: copy, walletAvailable: walletAvailable)
    analytics?.capture(.welcomePageViewed(variant: configuration.variant.analyticsValue, pitch: pages[0].kind.analyticsValue))
  }

  var selectedPage: FirstRunPitch { pages[selectedIndex] }
  var isBusy: Bool { phase == .requestingWallet }
  var isFinished: Bool {
    if case .finished = phase { return true }
    return false
  }

  var outcome: Outcome? {
    if case .finished(let outcome) = phase { return outcome }
    return nil
  }

  /// A device with Wallet opens on its own spending; otherwise on the demo.
  static func pages(copy: FirstRunCopy, walletAvailable: Bool) -> [FirstRunPitch] {
    let order: [FirstRunPitch.Kind] = walletAvailable ? [.wallet, .demo] : [.demo, .wallet]
    return order.map { copy.pitch($0, walletAvailable: walletAvailable) }
  }

  /// Flips to the second pitch once. Call from a view task so it is cancelled
  /// when the hero disappears.
  func runAutoAdvance() async {
    guard pages.count > 1, !hasInteracted else { return }
    do { try await sleep(configuration.autoAdvanceDelay) } catch { return }
    guard !hasInteracted, phase == .pitching, selectedIndex == 0 else { return }
    selectedIndex = 1
    capturePageView()
  }

  func select(_ index: Int) {
    guard phase == .pitching, pages.indices.contains(index) else { return }
    hasInteracted = true
    guard selectedIndex != index else { return }
    selectedIndex = index
    capturePageView()
  }

  func start(_ pitch: FirstRunPitch) async {
    guard phase == .pitching else { return }
    hasInteracted = true
    analytics?.capture(.welcomeAction(variant: configuration.variant.analyticsValue,
      pitch: pitch.kind.analyticsValue, action: pitch.action.analyticsValue))
    switch pitch.action {
    case .exploreDemo:
      finish(.exploreDemo)
    case .connectWallet:
      phase = .requestingWallet
      let authorized = await connectWallet()
      guard phase == .requestingWallet else { return }
      if authorized {
        finish(.walletConnected)
        analytics?.capture(.welcomeOutcome(variant: configuration.variant.analyticsValue, outcome: .walletConnected))
      } else {
        // Declining the system sheet falls back to the demo pitch, not a dead end.
        walletDeclined = true
        analytics?.capture(.welcomeOutcome(variant: configuration.variant.analyticsValue, outcome: .walletDeclined))
        phase = .pitching
        if let demo = pages.firstIndex(where: { $0.kind == .demo }) {
          selectedIndex = demo
          capturePageView()
        }
      }
    }
  }

  /// Design-comparison hook; replaces copy without restarting the hero.
  func apply(variant: FirstRunCopyVariant? = nil, region: FirstRunRegion? = nil) {
    let previousVariant = configuration.variant
    if let variant { configuration.variant = variant }
    if let region { configuration.region = region }
    market = FirstRunMarket.market(for: configuration.region)
    copy = FirstRunCopy.make(variant: configuration.variant, market: market, currentMonth: configuration.currentMonth)
    pages = Self.pages(copy: copy, walletAvailable: walletAvailable)
    if configuration.variant != previousVariant { capturePageView() }
  }

  private func capturePageView() {
    analytics?.capture(.welcomePageViewed(variant: configuration.variant.analyticsValue,
      pitch: selectedPage.kind.analyticsValue))
  }

  private func finish(_ outcome: Outcome) {
    markCompleted()
    phase = .finished(outcome)
  }
}

extension FirstRunCopyVariant {
  var analyticsValue: WelcomeVariant {
    switch self {
    case .instantReveal: .instantReveal
    case .storyCards: .storyCards
    case .heroOverview: .heroOverview
    }
  }
}

private extension FirstRunPitch.Kind {
  var analyticsValue: WelcomePitch {
    switch self {
    case .wallet: .wallet
    case .demo: .demo
    }
  }
}

private extension FirstRunPitch.Action {
  var analyticsValue: WelcomeAction {
    switch self {
    case .connectWallet: .connectWallet
    case .exploreDemo: .exploreDemo
    }
  }
}
