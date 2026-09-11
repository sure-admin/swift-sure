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
  weak var notificationLifecycle: (any AuthenticationNotificationLifecycle)?
  weak var financeData: FinanceDataStore?

  weak var appleCardConnection: AppleCardConnectionStore?
  var transactionHistoryFactories: [TransactionHistoryStoreFactory] = []

  func didConnect() async {
    financeData?.restoreSnapshotIfAvailable()
    await financeData?.refresh()
    await notificationLifecycle?.didConnect()
  }

  func prepareForConnectionChange() async {
    financeData?.disconnect(preservingSnapshot: true)
    await notificationLifecycle?.prepareForConnectionChange()
  }

  func didCommitConnectionChange() {
    financeData?.discardSnapshot()
    clearLocalData()
  }

  func prepareForLogout() async {
    clearLocalData()
    financeData?.disconnect()
    await notificationLifecycle?.prepareForLogout()
  }

  private func clearLocalData() {
    appleCardConnection?.disconnect()
    transactionHistoryFactories.forEach { $0.invalidateStores() }
  }

  func didLogOut() {
    clearLocalData()
    financeData?.disconnect()
  }
}
