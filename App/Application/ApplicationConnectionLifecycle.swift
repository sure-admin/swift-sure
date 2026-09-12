import Foundation

@MainActor
protocol SureConnectionLifecycleHandling: AnyObject {
  func didConnect() async
  func didCommitConnectionChange()
  func prepareForConnectionChange() async
  func prepareForLogout() async
  func didLogOut()
}

extension SureConnectionLifecycleHandling {
  func didCommitConnectionChange() { }
}

@MainActor
final class ApplicationConnectionLifecycle: SureConnectionLifecycleHandling {
  weak var analytics: (any UsageAnalytics)?
  weak var notificationLifecycle: (any AuthenticationNotificationLifecycle)?
  weak var financeData: FinanceDataStore?
  weak var spendingComparison: SpendingComparisonStore?

  weak var appleCardConnection: AppleCardConnectionStore?
  var transactionHistoryFactories: [TransactionHistoryStoreFactory] = []

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

  func didCommitConnectionChange() {
    analytics?.resetIdentity()
    financeData?.discardSnapshot()
    clearLocalData()
  }

  func prepareForLogout() async {
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
