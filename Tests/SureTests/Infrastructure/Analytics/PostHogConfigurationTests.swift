import Foundation
import Testing
@testable import Sure

@Suite("PostHog configuration")
struct PostHogConfigurationTests {
  @Test(arguments: ["", "http://analytics.example", "https://user:password@analytics.example", "https://analytics.example?key=secret", "https://analytics.example#fragment", "$(SURE_POSTHOG_HOST)"])
  func rejectsInvalidHosts(_ host: String) {
    #expect(PostHogConfiguration(projectToken: "phc_test", host: host) == nil)
  }

  @Test(arguments: ["", "$(SURE_POSTHOG_PROJECT_TOKEN)", "phx_personal_key", "phc_bad token"])
  func rejectsInvalidTokens(_ token: String) {
    #expect(PostHogConfiguration(projectToken: token, host: "https://analytics.example") == nil)
  }

  @Test func supportsExplicitSelfHostedDestination() throws {
    let config = try #require(PostHogConfiguration(projectToken: "phc_test", host: "https://analytics.example:8443/posthog"))
    #expect(config.host.absoluteString == "https://analytics.example:8443/posthog")
  }

  @Test @MainActor func consentPersistsWithoutSharedDefaults() throws {
    let suite = "AnalyticsTests-\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var preferences = UserDefaultsAnalyticsPreferences(defaults: defaults)
    #expect(preferences.analyticsEnabled)
    preferences.analyticsEnabled = true
    #expect(UserDefaultsAnalyticsPreferences(defaults: defaults).analyticsEnabled)
    preferences.analyticsEnabled = false
    #expect(!UserDefaultsAnalyticsPreferences(defaults: defaults).analyticsEnabled)
  }

  #if os(iOS)
  @Test @MainActor func disablesAutomaticCollection() throws {
    let settings = try #require(PostHogConfiguration(projectToken: "phc_test", host: "https://analytics.example"))
    let config = PostHogAnalyticsClient.makeConfig(settings)
    #expect(!config.captureApplicationLifecycleEvents)
    #expect(!config.captureScreenViews)
    #expect(!config.captureElementInteractions)
    #expect(!config.enableSwizzling)
    #expect(!config.sessionReplay)
    #expect(!config.surveys)
    #expect(!config.preloadFeatureFlags)
    #expect(!config.debug)
  }
  #endif
}
