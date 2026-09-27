#if os(iOS)
import Sentry

@MainActor
final class SentryDiagnosticsClient: DiagnosticsClient {
  private let configuration: SentryDiagnosticsConfiguration
  private var isStarted = false

  init(configuration: SentryDiagnosticsConfiguration) {
    self.configuration = configuration
  }

  func start() {
    guard !isStarted else { return }
    isStarted = true
    let configuration = self.configuration
    SentrySDK.start { options in Self.configure(options, for: configuration) }
  }

  /// Sentry's defaults collect request URLs, UI and network breadcrumbs,
  /// screenshots, and view hierarchies. In a finance client each of those can
  /// carry a self-hosted server address or an account balance, so every
  /// automatic collector stays off: the crash handler and the closed
  /// `DiagnosticRecord` vocabulary are the only things that reach the network.
  nonisolated static func configure(_ options: Sentry.Options, for configuration: SentryDiagnosticsConfiguration) {
    options.dsn = configuration.dsn.absoluteString
    options.environment = configuration.environment
    options.debug = false
    options.sendDefaultPii = false

    // Anything that can capture the screen, the view tree, or a request URL.
    options.attachScreenshot = false
    options.attachViewHierarchy = false
    options.enableSwizzling = false
    options.enableNetworkTracking = false
    options.enableNetworkBreadcrumbs = false
    options.enableCaptureFailedRequests = false
    options.enableAutoBreadcrumbTracking = false
    options.enableUserInteractionTracing = false
    options.enableFileIOTracing = false
    options.enableCoreDataTracing = false
    options.sessionReplay.sessionSampleRate = 0
    options.sessionReplay.onErrorSampleRate = 0
    options.maxBreadcrumbs = 0
    options.beforeBreadcrumb = { _ in nil }

    // No performance, release-health, or hang telemetry: the app sends events
    // it composes itself, plus crashes.
    options.enableAutoPerformanceTracing = false
    options.enableAutoSessionTracking = false
    options.enableWatchdogTerminationTracking = false
    options.enableAppHangTracking = false
    options.enableSpotlight = false
    options.tracesSampleRate = 0

    options.enableCrashHandler = true
    options.attachStacktrace = true

    options.beforeSendLog = { log in
      guard DiagnosticRecord.messages.contains(log.body) else { return nil }
      return log
    }
    // A crash report is the one event the app does not compose itself, so the
    // fields that could carry an address or an identity are cleared here rather
    // than trusted to stay empty.
    options.beforeSend = { event in
      event.user = nil
      event.request = nil
      event.breadcrumbs = nil
      event.serverName = nil
      return event
    }
  }

  nonisolated static func makeOptions(for configuration: SentryDiagnosticsConfiguration) -> Sentry.Options {
    let options = Sentry.Options()
    configure(options, for: configuration)
    return options
  }

  func log(_ record: DiagnosticRecord) {
    guard isStarted else { return }
    let message = record.message
    let attributes: [String: Any] = record.attributes
    switch record.level {
    case .info: SentrySDK.logger.info(message, attributes: attributes)
    case .error: SentrySDK.logger.error(message, attributes: attributes)
    }
  }

  func stop() {
    guard isStarted else { return }
    isStarted = false
    // Closing flushes what is already queued and uninstalls the crash handler.
    SentrySDK.close()
  }
}
#endif
