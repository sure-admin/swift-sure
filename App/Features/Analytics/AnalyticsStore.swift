import Observation

@MainActor
@Observable
final class AnalyticsStore: UsageAnalyticsControlling {
  private(set) var isEnabled: Bool
  var isAvailable: Bool { client != nil }
  private var preferences: any AnalyticsPreferences
  private let client: (any AnalyticsClient)?

  init(preferences: any AnalyticsPreferences, client: (any AnalyticsClient)?) {
    self.preferences = preferences
    self.client = client
    isEnabled = client != nil && preferences.analyticsEnabled
    if isEnabled { client?.start() }
  }

  func setEnabled(_ enabled: Bool) {
    guard isAvailable, enabled != isEnabled else { return }
    preferences.analyticsEnabled = enabled
    isEnabled = enabled
    if enabled {
      client?.start()
    } else {
      client?.stop()
    }
  }

  func capture(_ event: UsageEvent) {
    guard isEnabled else { return }
    client?.capture(event)
  }

  func resetIdentity() {
    guard isEnabled else { return }
    client?.resetIdentity()
  }
}
