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
  /// Budget reads may fail even when downloaded values remain visible.
  case budgetLoadFailed(failure: DataFailure, hasDownloadedData: Bool)
  /// Wallet errors are classified locally. A server-supplied error code must
  /// be converted to the closed rejection vocabulary before constructing this.
  case walletSyncFailed(
    operation: DiagnosticWalletOperation,
    failure: DiagnosticWalletFailure,
    rejection: FinanceKitBatchRejection? = nil,
    field: FinanceKitEventValidationIssue.Field? = nil,
    rule: DiagnosticWalletValidationRule? = nil
  )

  var message: String {
    switch self {
    case .launched: "app.launched"
    case .cleanupFailed: "cleanup.failed"
    case .transactionHistoryLoadFailed: "transactions.load_failed"
    case .budgetLoadFailed: "budgets.load_failed"
    case .walletSyncFailed: "wallet.sync_failed"
    }
  }

  var level: DiagnosticLevel {
    switch self {
    case .launched: .info
    case .cleanupFailed, .transactionHistoryLoadFailed, .budgetLoadFailed, .walletSyncFailed: .error
    }
  }

  var attributes: [String: String] {
    switch self {
    case .launched: return [:]
    case .cleanupFailed(let operation): return ["operation": operation.rawValue]
    case .transactionHistoryLoadFailed(let source, let scope, let failure): return [
      "source": source.rawValue,
      "scope": scope.rawValue,
      "failure": failure.diagnosticCode
    ]
    case .budgetLoadFailed(let failure, let hasDownloadedData): return [
      "failure": failure.diagnosticCode,
      "downloaded_data": hasDownloadedData ? "available" : "none"
    ]
    case .walletSyncFailed(let operation, let failure, let rejection, let field, let rule):
      var values = ["operation": operation.rawValue, "failure": failure.rawValue]
      if let rejection { values["rejection"] = rejection.rawValue }
      if let field { values["field"] = field.rawValue }
      if let rule { values["rule"] = rule.rawValue }
      return values
    }
  }

  var issueFingerprint: [String]? {
    switch self {
    case .transactionHistoryLoadFailed(let source, let scope, let failure):
      return [message, source.rawValue, scope.rawValue, failure.diagnosticCode]
    case .budgetLoadFailed(let failure, _):
      return [message, failure.diagnosticCode]
    case .walletSyncFailed(let operation, let failure, let rejection, let field, let rule):
      return [message, operation.rawValue, failure.rawValue, rejection?.rawValue ?? "none",
        field?.rawValue ?? "none", rule?.rawValue ?? "none"]
    case .launched, .cleanupFailed: return nil
    }
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
    ).message,
    DiagnosticRecord.budgetLoadFailed(failure: .unknown, hasDownloadedData: false).message,
    DiagnosticRecord.walletSyncFailed(operation: .sync, failure: .unknown).message
  ])
}

enum DiagnosticWalletOperation: String, CaseIterable {
  case disconnect, enroll, enrollmentCleanup = "enrollment_cleanup", sync, status, repair, renew, resolve
}

enum DiagnosticWalletFailure: String, CaseIterable {
  case authentication, authorization, conflict, invalidResponse = "invalid_response"
  case publisherRevoked = "publisher_revoked", rateLimited = "rate_limited"
  case rejected, server, tooLarge = "too_large", offline, subscription
  case validation, malformed, unavailable, persistence, unknown
  case eventTooLarge = "event_too_large", historyTokenInvalid = "history_token_invalid"
  case invalidAmount = "invalid_amount", invalidCheckpoint = "invalid_checkpoint"
  case invalidReceipt = "invalid_receipt", invalidState = "invalid_state"
  case sequenceExhausted = "sequence_exhausted", streamFailed = "stream_failed"
  case unsupportedSourceValue = "unsupported_source_value"
  case repairRequired = "repair_required", disconnectPending = "disconnect_pending"
}

enum DiagnosticWalletValidationRule: String, CaseIterable {
  case requiredForBooked = "required_for_booked", nonblank, textLimit = "text_limit"
  case supportedStatus = "supported_status", notAfterCapture = "not_after_capture"
  case uniqueIdentity = "unique_identity", readablePayload = "readable_payload"

  init(_ rule: FinanceKitEventValidationIssue.Rule) {
    self = switch rule {
    case .requiredForBooked: .requiredForBooked
    case .nonblank: .nonblank
    case .textLimit: .textLimit
    case .supportedStatus: .supportedStatus
    case .notAfterCapture: .notAfterCapture
    case .uniqueIdentity: .uniqueIdentity
    case .readablePayload: .readablePayload
    }
  }
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
