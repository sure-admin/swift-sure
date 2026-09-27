import Foundation
import Testing
@testable import Sure

@Suite("Sentry diagnostics configuration")
struct SentryDiagnosticsConfigurationTests {
  @Test(arguments: [
    "",
    "$(SURE_SENTRY_DSN)",
    "http://key@o1.ingest.example/1",
    "https://o1.ingest.example/1",
    "https://@o1.ingest.example/1",
    "https://key:secret@o1.ingest.example/1",
    "https://key@o1.ingest.example",
    "https://key@o1.ingest.example/",
    "https://key@o1.ingest.example/1?token=secret",
    "https://key@o1.ingest.example/1#fragment",
    "https://key@ o1.ingest.example/1"
  ])
  func rejectsInvalidDSNs(_ dsn: String) {
    #expect(SentryDiagnosticsConfiguration(dsn: dsn) == nil)
  }

  @Test func acceptsAPublicDSN() throws {
    let configuration = try #require(SentryDiagnosticsConfiguration(dsn: "https://publickey@o1.ingest.example/1"))
    #expect(configuration.dsn.absoluteString == "https://publickey@o1.ingest.example/1")
  }

  @Test func acceptsASelfHostedPathPrefix() throws {
    let configuration = try #require(
      SentryDiagnosticsConfiguration(dsn: " https://publickey@sentry.example:8443/relay/42\n")
    )
    #expect(configuration.dsn.absoluteString == "https://publickey@sentry.example:8443/relay/42")
  }

  @Test func rejectsAnUnusableEnvironment() {
    #expect(SentryDiagnosticsConfiguration(dsn: "https://key@o1.ingest.example/1", environment: "") == nil)
    #expect(SentryDiagnosticsConfiguration(dsn: "https://key@o1.ingest.example/1", environment: "two words") == nil)
  }

  @Test func missingInfoDictionaryKeyDisablesDiagnostics() {
    #expect(SentryDiagnosticsConfiguration(bundle: Bundle(for: DiagnosticsBundleMarker.self)) == nil)
  }

  @Test @MainActor func consentPersistsWithoutSharedDefaults() throws {
    let suite = "DiagnosticsTests-\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var preferences = UserDefaultsDiagnosticsPreferences(defaults: defaults)
    #expect(preferences.diagnosticsEnabled)
    preferences.diagnosticsEnabled = false
    #expect(!UserDefaultsDiagnosticsPreferences(defaults: defaults).diagnosticsEnabled)
    preferences.diagnosticsEnabled = true
    #expect(UserDefaultsDiagnosticsPreferences(defaults: defaults).diagnosticsEnabled)
  }

  #if os(iOS)
  @Test func disablesEveryAutomaticCollector() throws {
    let configuration = try #require(SentryDiagnosticsConfiguration(dsn: "https://key@o1.ingest.example/1"))
    let options = SentryDiagnosticsClient.makeOptions(for: configuration)
    #expect(options.dsn == "https://key@o1.ingest.example/1")
    #expect(!options.sendDefaultPii)
    #expect(!options.attachScreenshot)
    #expect(!options.attachViewHierarchy)
    #expect(!options.enableSwizzling)
    #expect(!options.enableNetworkTracking)
    #expect(!options.enableNetworkBreadcrumbs)
    #expect(!options.enableCaptureFailedRequests)
    #expect(!options.enableAutoBreadcrumbTracking)
    #expect(!options.enableUserInteractionTracing)
    #expect(!options.enableAutoPerformanceTracing)
    #expect(!options.enableAutoSessionTracking)
    #expect(!options.enableWatchdogTerminationTracking)
    #expect(!options.enableSpotlight)
    #expect(!options.debug)
    #expect(options.maxBreadcrumbs == 0)
    #expect(options.sessionReplay.sessionSampleRate == 0)
    #expect(options.sessionReplay.onErrorSampleRate == 0)
  }
  #endif
}

private final class DiagnosticsBundleMarker {}
