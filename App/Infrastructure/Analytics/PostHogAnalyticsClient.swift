#if os(iOS)
import PostHog

@MainActor
final class PostHogAnalyticsClient: AnalyticsClient {
  private let configuration: PostHogConfiguration
  private var sdk: PostHogSDK?

  init(configuration: PostHogConfiguration) {
    self.configuration = configuration
  }

  func start() {
    guard sdk == nil else { return }
    let config = Self.makeConfig(configuration)
    sdk = PostHogSDK.with(config)
    sdk?.optIn()
  }

  static func makeConfig(_ configuration: PostHogConfiguration) -> PostHogConfig {
    let config = PostHogConfig(projectToken: configuration.projectToken, host: configuration.host.absoluteString)
    // Explicit events only. Never inspect finance UI, network requests, or assistant text.
    config.captureApplicationLifecycleEvents = false
    config.captureScreenViews = false
    config.captureElementInteractions = false
    config.enableSwizzling = false
    config.sessionReplay = false
    config.surveys = false
    config.rageClickConfig.enabled = false
    config.preloadFeatureFlags = false
    config.sendFeatureFlagEvent = false
    config.setDefaultPersonProperties = false
    config.personProfiles = .never
    config.errorTrackingConfig.autoCapture = false
    config.debug = false
    config.maxQueueSize = 100
    config.setBeforeSend { event in
      guard event.event == "app_opened" || event.event == "screen_viewed" else { return nil }
      return event
    }
    return config
  }

  func capture(_ event: UsageEvent) {
    sdk?.capture(event.name, properties: event.properties)
  }

  func resetIdentity() {
    sdk?.reset()
  }

  func stop() {
    sdk?.optOut()
    sdk?.close()
    sdk = nil
  }
}
#endif
