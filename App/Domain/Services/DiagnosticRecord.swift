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
  /// A transaction history request reached the user-visible failure state
  /// without a downloaded-data fallback. Only fixed classifications cross the
  /// diagnostics boundary; the account and underlying error stay on device.
  case transactionHistoryLoadFailed(
    source: DiagnosticTransactionSource,
    scope: DiagnosticTransactionScope,
    failure: DataFailure
  )

  var message: String {
    switch self {
    case .launched: "app.launched"
    case .cleanupFailed: "cleanup.failed"
    case .transactionHistoryLoadFailed: "transactions.load_failed"
    }
  }

  var level: DiagnosticLevel {
    switch self {
    case .launched: .info
    case .cleanupFailed, .transactionHistoryLoadFailed: .error
    }
  }

  var attributes: [String: String] {
    switch self {
    case .launched: [:]
    case .cleanupFailed(let operation): ["operation": operation.rawValue]
    case .transactionHistoryLoadFailed(let source, let scope, let failure): [
      "source": source.rawValue,
      "scope": scope.rawValue,
      "failure": failure.diagnosticCode
    ]
    }
  }

  var issueFingerprint: [String]? {
    guard case .transactionHistoryLoadFailed(let source, let scope, let failure) = self else { return nil }
    return [message, source.rawValue, scope.rawValue, failure.diagnosticCode]
  }

  /// Logs and issue events use separate Sentry pipelines. Unrecognized SDK
  /// logs must never be admitted because a message resembles an issue title.
  static let logMessages: Set<String> = [
    DiagnosticRecord.launched.message,
    DiagnosticRecord.cleanupFailed(.appDataReset).message
  ]

  static let messages: Set<String> = logMessages.union([
    DiagnosticRecord.transactionHistoryLoadFailed(
      source: .sure, scope: .recentActivity, failure: .unknown
    ).message
  ])
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

enum DiagnosticTransactionSource: String, CaseIterable {
  case sure, wallet
}

enum DiagnosticTransactionScope: String, CaseIterable {
  case account
  case recentActivity = "recent_activity"
}

private extension DataFailure {
  var diagnosticCode: String {
    switch self {
    case .cancelled: "cancelled"
    case .offline: "offline"
    case .authentication: "authentication"
    case .authorization: "authorization"
    case .subscription: "subscription"
    case .unavailable: "unavailable"
    case .validation: "validation"
    case .malformed: "malformed"
    case .rateLimited: "rate_limited"
    case .server: "server"
    case .persistence: "persistence"
    case .cleanup: "cleanup"
    case .unknown: "unknown"
    }
  }
}
