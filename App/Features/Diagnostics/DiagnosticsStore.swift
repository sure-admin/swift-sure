import Observation

@MainActor
@Observable
final class DiagnosticsStore: DiagnosticsControlling {
  private(set) var isEnabled: Bool
  var isAvailable: Bool { client != nil }
  private var preferences: any DiagnosticsPreferences
  private let client: (any DiagnosticsClient)?

  init(preferences: any DiagnosticsPreferences, client: (any DiagnosticsClient)?) {
    self.preferences = preferences
    self.client = client
    isEnabled = client != nil && preferences.diagnosticsEnabled
    if isEnabled { client?.start() }
  }

  func setEnabled(_ enabled: Bool) {
    guard isAvailable, enabled != isEnabled else { return }
    preferences.diagnosticsEnabled = enabled
    isEnabled = enabled
    if enabled {
      client?.start()
    } else {
      client?.stop()
    }
  }

  func log(_ record: DiagnosticRecord) {
    guard isEnabled else { return }
    client?.log(record)
  }
}
