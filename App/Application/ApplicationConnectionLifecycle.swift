import Foundation

@MainActor
protocol SureConnectionLifecycleHandling: AnyObject {
  func didConnect() async
  func prepareForConnectionChange() async
  func prepareForLogout() async
  func didLogOut()
}

@MainActor
final class ApplicationConnectionLifecycle: SureConnectionLifecycleHandling {
  weak var notificationLifecycle: (any AuthenticationNotificationLifecycle)?
  weak var financeData: FinanceDataStore?

  func didConnect() async {
    await notificationLifecycle?.didConnect()
  }

  func prepareForConnectionChange() async {
    financeData?.disconnect()
    await notificationLifecycle?.prepareForConnectionChange()
  }

  func prepareForLogout() async {
    financeData?.disconnect()
    await notificationLifecycle?.prepareForLogout()
  }

  func didLogOut() {
    financeData?.disconnect()
  }
}
