import Foundation

@MainActor
final class ApplicationConnectionLifecycle: SureConnectionLifecycleHandling {
  weak var analytics: (any UsageAnalytics)?
  var clearOfflineResponses: () async -> Void = {}
  weak var notificationLifecycle: (any AuthenticationNotificationLifecycle)?
  weak var financeData: FinanceDataStore?
  weak var spendingComparison: SpendingComparisonStore?

  weak var appleCardConnection: AppleCardConnectionStore?
  var transactionHistoryFactories: [TransactionHistoryStoreFactory] = []

  func restoreInitialState(isExplicitlySignedOut: Bool) {
    // Wallet reconnect preferences already reflect the latest explicit decision.
    // A persisted Sure logout must not undo Wallet access granted afterward.
    if isExplicitlySignedOut { financeData?.disconnect() }
  }

  func didConnect() async {
    financeData?.restoreSnapshotIfAvailable()
    await financeData?.refresh()
    await spendingComparison?.refresh()
    await notificationLifecycle?.didConnect()
  }

  func prepareForConnectionChange() async {
    spendingComparison?.invalidate()
    financeData?.disconnect(preservingSnapshot: true)
    await notificationLifecycle?.prepareForConnectionChange()
  }

  func didCommitConnectionChange() async {
    await clearOfflineResponses()
    analytics?.resetIdentity()
    financeData?.discardSnapshot()
    clearLocalData()
  }

  func prepareForLogout() async {
    await clearOfflineResponses()
    clearLocalData()
    financeData?.disconnect()
    await notificationLifecycle?.prepareForLogout()
  }

  private func clearLocalData() {
    spendingComparison?.invalidate()
    appleCardConnection?.disconnect()
    transactionHistoryFactories.forEach { $0.invalidateStores() }
  }

  func didLogOut() {
    analytics?.resetIdentity()
    clearLocalData()
    financeData?.disconnect()
  }
}
