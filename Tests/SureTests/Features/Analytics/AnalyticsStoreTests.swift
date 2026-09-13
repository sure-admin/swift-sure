import Testing
@testable import Sure

@MainActor
@Suite("Usage analytics consent")
struct AnalyticsStoreTests {
  @Test func disabledNeverStartsOrCaptures() {
    let client = AnalyticsSpy()
    let store = AnalyticsStore(preferences: MemoryAnalyticsPreferences(), client: client)
    store.capture(.appOpened)
    store.resetIdentity()
    #expect(!store.isEnabled)
    #expect(client.calls.isEmpty)
  }

  @Test func consentStartsOnceAndRevocationStopsCapture() {
    let preferences = MemoryAnalyticsPreferences()
    let client = AnalyticsSpy()
    let store = AnalyticsStore(preferences: preferences, client: client)
    store.setEnabled(true)
    store.setEnabled(true)
    store.capture(.screenViewed(.accounts))
    store.resetIdentity()
    #expect(preferences.analyticsEnabled)
    store.setEnabled(false)
    store.capture(.appOpened)
    store.resetIdentity()
    store.setEnabled(false)
    #expect(!preferences.analyticsEnabled)
    #expect(client.calls == ["start", "screen_viewed", "reset", "stop"])
    store.setEnabled(true)
    #expect(client.calls.last == "start")
  }

  @Test func savedConsentIsRestored() {
    let preferences = MemoryAnalyticsPreferences()
    preferences.analyticsEnabled = true
    let client = AnalyticsSpy()
    let store = AnalyticsStore(preferences: preferences, client: client)
    #expect(store.isEnabled)
    #expect(client.calls == ["start"])
  }

  @Test func missingConfigurationRemainsDisabled() {
    let preferences = MemoryAnalyticsPreferences()
    preferences.analyticsEnabled = true
    let store = AnalyticsStore(preferences: preferences, client: nil)
    store.setEnabled(true)
    #expect(!store.isEnabled)
    #expect(!store.isAvailable)
  }

  @Test func eventVocabularyContainsOnlyUsage() {
    #expect(UsageEvent.appOpened.properties.isEmpty)
    for screen in UsageScreen.allCases {
      #expect(UsageEvent.screenViewed(screen).properties == ["screen": screen.rawValue])
    }
  }

  @Test func identityRotatesOnlyAfterCommittedChanges() async {
    let client = AnalyticsSpy()
    let lifecycle = ApplicationConnectionLifecycle()
    lifecycle.analytics = client
    await lifecycle.prepareForConnectionChange()
    #expect(client.calls.isEmpty)
    await lifecycle.didCommitConnectionChange()
    lifecycle.didLogOut()
    #expect(client.calls == ["reset", "reset"])
  }
}

@MainActor
private final class MemoryAnalyticsPreferences: AnalyticsPreferences {
  var analyticsEnabled = false
}

@MainActor
private final class AnalyticsSpy: AnalyticsClient {
  var calls: [String] = []
  func start() { calls.append("start") }
  func stop() { calls.append("stop") }
  func capture(_ event: UsageEvent) { calls.append(event.name) }
  func resetIdentity() { calls.append("reset") }
}
