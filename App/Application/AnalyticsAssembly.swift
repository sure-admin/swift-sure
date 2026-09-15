import Foundation

@MainActor
enum AnalyticsAssembly {
  static func make() -> AnalyticsStore {
    let analyticsClient: (any AnalyticsClient)?
    #if os(iOS)
    // Test hosts must not start SDK networking, even with a persisted preference.
    if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
       let configuration = PostHogConfiguration(bundle: .main) {
      analyticsClient = PostHogAnalyticsClient(configuration: configuration)
    } else {
      analyticsClient = nil
    }
    #else
    analyticsClient = nil
    #endif
    let analytics = AnalyticsStore(
      preferences: UserDefaultsAnalyticsPreferences(defaults: .standard),
      client: analyticsClient
    )
    analytics.capture(.appOpened)
    return analytics
  }
}
