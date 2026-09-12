@MainActor
protocol AnalyticsPreferences {
  var analyticsEnabled: Bool { get set }
}

@MainActor
protocol AnalyticsClient: UsageAnalytics {
  func start()
  func stop()
}

@MainActor
protocol UsageAnalyticsControlling: UsageAnalytics {
  var isEnabled: Bool { get }
  var isAvailable: Bool { get }
  func setEnabled(_ enabled: Bool)
}
