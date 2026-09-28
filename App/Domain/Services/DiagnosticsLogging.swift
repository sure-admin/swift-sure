@MainActor
protocol DiagnosticsPreferences {
  var diagnosticsEnabled: Bool { get set }
}

/// Destination for operational diagnostics. Implementations receive only the
/// closed `DiagnosticRecord` vocabulary, so a remote destination can never be
/// handed a server address, a credential, a monetary value, a Sure identifier,
/// or assistant text.
@MainActor
protocol DiagnosticsLogging: AnyObject {
  func log(_ record: DiagnosticRecord)
}

@MainActor
protocol DiagnosticsClient: DiagnosticsLogging {
  func start()
  func stop()
}

@MainActor
protocol DiagnosticsControlling: DiagnosticsLogging {
  var isEnabled: Bool { get }
  var isAvailable: Bool { get }
  func setEnabled(_ enabled: Bool)
}
