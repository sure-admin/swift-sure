/// Closed diagnostics vocabulary. Every record resolves to a fixed message and
/// a fixed attribute set, so no call site can route a server response, an error
/// description, or a financial value into a remote diagnostics destination.
enum DiagnosticRecord: Equatable {
  /// One per process launch, so a diagnostics destination can distinguish a
  /// silent install from one that never reports.
  case launched
  /// Local cleanup that failed after a Sure session ended. These currently
  /// collapse into a single user-facing `DataFailure.cleanup`, which hides
  /// which step actually failed.
  case cleanupFailed(DiagnosticOperation)

  var message: String {
    switch self {
    case .launched: "app.launched"
    case .cleanupFailed: "cleanup.failed"
    }
  }

  var level: DiagnosticLevel {
    switch self {
    case .launched: .info
    case .cleanupFailed: .error
    }
  }

  var attributes: [String: String] {
    switch self {
    case .launched: [:]
    case .cleanupFailed(let operation): ["operation": operation.rawValue]
    }
  }

  /// Every message the app may emit. A destination drops anything else,
  /// including records an SDK would otherwise contribute on its own.
  static let messages: Set<String> = [
    DiagnosticRecord.launched.message,
    DiagnosticRecord.cleanupFailed(.appDataReset).message
  ]
}

enum DiagnosticLevel: String {
  case info, error
}

/// Local work that can fail after a Sure session ends. A case names the step
/// only; it never identifies a server, an account, or a record.
enum DiagnosticOperation: String, CaseIterable {
  case offlineResponses = "offline_responses"
  case walletPublisherDisconnect = "wallet_publisher_disconnect"
  case walletBackgroundDelivery = "wallet_background_delivery"
  case appDataReset = "app_data_reset"
}
