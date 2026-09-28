import Foundation

@MainActor
enum DiagnosticsAssembly {
  static func make() -> DiagnosticsStore {
    let diagnosticsClient: (any DiagnosticsClient)?
    #if os(iOS)
    // Test hosts must not start SDK networking or install a crash handler,
    // even with a persisted preference.
    if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
       let configuration = SentryDiagnosticsConfiguration(bundle: .main) {
      diagnosticsClient = SentryDiagnosticsClient(configuration: configuration)
    } else {
      diagnosticsClient = nil
    }
    #else
    diagnosticsClient = nil
    #endif
    let diagnostics = DiagnosticsStore(
      preferences: UserDefaultsDiagnosticsPreferences(defaults: .standard),
      client: diagnosticsClient
    )
    diagnostics.log(.launched)
    return diagnostics
  }
}
