import Foundation

@MainActor
final class ApplicationConnectionLifecycle: SureConnectionLifecycleHandling {
  weak var analytics: (any UsageAnalytics)?
  private(set) var dataCleanupFailure: DataFailure?
  var clearOfflineResponses: () async throws -> Void = {}
  var resetAppData: () throws -> Void = {}
  weak var notificationLifecycle: (any AuthenticationNotificationLifecycle)?
  weak var financeData: FinanceDataStore?
  weak var financeKitSync: FinanceKitSyncStore?
  weak var spendingComparison: SpendingComparisonStore?
  var financeKitPublisher: (any FinanceKitPublisherLifecycleHandling)?

  weak var appleCardConnection: AppleCardConnectionStore?
  var transactionHistoryFactories: [TransactionHistoryStoreFactory] = []

  func restoreInitialState(isExplicitlySignedOut: Bool) {
    // Sure session cleanup never revokes independent on-device Wallet access.
    if isExplicitlySignedOut {
      dataCleanupFailure = nil
      do { try financeKitPublisher?.blockBackgroundDelivery() }
      catch { dataCleanupFailure = .cleanup }
      financeData?.disconnect()
      Task {
        await clearDownloadedData()
        await clearFinanceKitPublisher()
      }
    }
  }

  func didConnect() async {
    await appleCardConnection?.refresh()
    await financeData?.restoreSnapshotIfAvailable()
    await financeData?.refresh()
    await spendingComparison?.refresh()
    await notificationLifecycle?.didConnect()
  }

  func prepareForConnectionChange() async {
    await financeKitPublisher?.suspend()
    spendingComparison?.invalidate()
    financeData?.disconnect(preservingSnapshot: true)
    await notificationLifecycle?.prepareForConnectionChange()
  }

  func didFailConnectionChange() async {
    await financeKitPublisher?.resumeIfConfigured()
    await spendingComparison?.refresh()
  }

  func didCommitConnectionChange() async {
    dataCleanupFailure = nil
    await clearDownloadedData()
    await clearFinanceKitPublisher()
    analytics?.resetIdentity()
    clearLocalData()
  }

  func prepareForLogout() async {
    dataCleanupFailure = nil
    await clearDownloadedData()
    await clearFinanceKitPublisher()
    clearLocalData()
    financeData?.disconnect()
    await notificationLifecycle?.prepareForLogout()
  }

  private func clearDownloadedData() async {
    do { try await clearOfflineResponses() }
    catch { dataCleanupFailure = .cleanup }
  }

  private func clearFinanceKitPublisher() async {
    do { try await financeKitPublisher?.disconnect() }
    catch { dataCleanupFailure = .cleanup }
  }

  private func clearLocalData() {
    spendingComparison?.invalidate()
    transactionHistoryFactories.forEach { $0.invalidateStores() }
  }

  func didLogOut() {
    analytics?.resetIdentity()
    clearLocalData()
    financeData?.disconnect()
    financeKitSync?.resetForLogout()
    do { try resetAppData() }
    catch { dataCleanupFailure = .cleanup }
  }
}
