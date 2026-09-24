@MainActor
protocol FinanceKitSyncPreferences: AnyObject {
  /// nil allows migration from a publisher whose consent was already recorded.
  var consentAcknowledged: Bool? { get set }
  var consentWithdrawalPending: Bool { get set }
}
