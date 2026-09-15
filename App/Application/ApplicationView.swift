import SwiftUI

#if os(iOS)
import UIKit
#endif

struct ApplicationView: View {
  @State private var subscriptionAccess: SubscriptionAccessStore
  @Environment(\.scenePhase) private var scenePhase
  @State private var connection: SureConnection
  @State private var financeData: FinanceDataStore
  @State private var spendingComparison: SpendingComparisonStore
  @State private var appleCardConnection: AppleCardConnectionStore
  private var analytics: AnalyticsStore
  private var notificationManager: NotificationManager
  private var oauthService: PasskeyOAuthService
  private var mobileSSOService: MobileSSOAuthService
  private var remoteAssistant: any RemoteAssistantClient
  private var transactionHistoryStoreFactory: TransactionHistoryStoreFactory
  private var localTransactionHistoryStoreFactory: TransactionHistoryStoreFactory

  init(configureNotifications: (NotificationManager, BackendAccessGate) -> Void = { _, _ in }) {
    let analytics = AnalyticsAssembly.make()
    let services = ConnectionAssembly()
    let devices = DeviceAssembly(connection: services)
    let finance = FinanceAssembly(connection: services, syncInsights: devices.syncInsights)
    let lifecycle = services.lifecycle
    lifecycle.analytics = analytics
    lifecycle.notificationLifecycle = devices.notifications
    lifecycle.financeData = finance.financeData
    lifecycle.spendingComparison = finance.spendingComparison
    lifecycle.appleCardConnection = finance.appleCardConnection
    lifecycle.transactionHistoryFactories = [finance.transactionHistoryStoreFactory, finance.localTransactionHistoryStoreFactory]
    lifecycle.restoreInitialState(isExplicitlySignedOut: services.initialState.isExplicitlySignedOut)
    _subscriptionAccess = State(initialValue: services.subscriptionAccess)
    _connection = State(initialValue: services.connection)
    _financeData = State(initialValue: finance.financeData)
    _spendingComparison = State(initialValue: finance.spendingComparison)
    _appleCardConnection = State(initialValue: finance.appleCardConnection)
    self.analytics = analytics
    notificationManager = devices.notifications
    oauthService = services.oauthService
    mobileSSOService = services.mobileSSOService
    remoteAssistant = finance.remoteAssistant
    transactionHistoryStoreFactory = finance.transactionHistoryStoreFactory
    localTransactionHistoryStoreFactory = finance.localTransactionHistoryStoreFactory
    configureNotifications(devices.notifications, services.accessGate)
    devices.activate()
  }

  var body: some View {
    Group {
      ContentView(
        subscriptionAccess: subscriptionAccess,
        connection: connection,
        analytics: analytics,
        financeData: financeData,
        spendingComparison: spendingComparison,
        appleCardConnection: appleCardConnection,
        notificationManager: notificationManager,
        remoteAssistant: remoteAssistant,
        transactionHistoryStoreFactory: transactionHistoryStoreFactory,
        localTransactionHistoryStoreFactory: localTransactionHistoryStoreFactory,
        makeAssistantMessageID: { UUID() },
        now: { .now }
      )
      .task { await subscriptionAccess.monitor() }
      .onChange(of: scenePhase) { _, phase in
        if phase == .active { Task { await subscriptionAccess.refresh() } }
      }
      .onChange(of: subscriptionAccess.hasAccess) { _, allowed in
        if allowed { Task {
          await financeData.refresh()
          await notificationManager.applicationDidFinishLaunching()
          await notificationManager.didConnect()
        } }
        else {
          financeData.suspendSync()
          connection.suspendAuthentication()
          oauthService.cancelAuthentication()
          mobileSSOService.cancelAuthentication()
        }
      }
      .onOpenURL { url in
        guard subscriptionAccess.hasAccess else { return }
        mobileSSOService.handleOpenURL(url)
      }
    }
  }
}
