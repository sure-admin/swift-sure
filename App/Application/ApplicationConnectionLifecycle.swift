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
  }

  func prepareForLogout() async {
    financeData?.disconnect()
    await notificationLifecycle?.prepareForLogout()
  }

  func didLogOut() {
    financeData?.disconnect()
  }
}
