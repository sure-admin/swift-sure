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
  @State private var firstRun: FirstRunStore?
  private var analytics: AnalyticsStore
  private var notificationManager: NotificationManager
  private var oauthService: PasskeyOAuthService
  private var mobileSSOService: MobileSSOAuthService
  private var remoteAssistant: any RemoteAssistantClient
  private var financeKitPublisher: any FinanceKitPublisherLifecycleHandling
  @State private var financeKitSync: FinanceKitSyncStore
  private var transactionHistoryStoreFactory: TransactionHistoryStoreFactory
  private var localTransactionHistoryStoreFactory: TransactionHistoryStoreFactory
  private var makeFirstRun: () -> FirstRunStore?

  init(configureNotifications: (NotificationManager, BackendAccessGate) -> Void = { _, _ in }) {
    let analytics = AnalyticsAssembly.make()
    let services = ConnectionAssembly()
    let devices = DeviceAssembly(connection: services)
    let finance = FinanceAssembly(connection: services, syncInsights: devices.syncInsights)
    let lifecycle = services.lifecycle
    lifecycle.resetAppData = { try ApplicationDataResetter().reset() }
    lifecycle.analytics = analytics
    lifecycle.notificationLifecycle = devices.notifications
    lifecycle.financeData = finance.financeData
    lifecycle.financeKitSync = finance.financeKitSync
    lifecycle.spendingComparison = finance.spendingComparison
    lifecycle.appleCardConnection = finance.appleCardConnection
    lifecycle.financeKitPublisher = finance.financeKitPublisher
    lifecycle.transactionHistoryFactories = [finance.transactionHistoryStoreFactory, finance.localTransactionHistoryStoreFactory]
    lifecycle.restoreInitialState(isExplicitlySignedOut: services.initialState.isExplicitlySignedOut)
    _firstRun = State(initialValue: FirstRunAssembly(connection: services, finance: finance).store)
    makeFirstRun = { FirstRunAssembly(connection: services, finance: finance).store }
    _subscriptionAccess = State(initialValue: services.subscriptionAccess)
    _connection = State(initialValue: services.connection)
    _financeData = State(initialValue: finance.financeData)
    _spendingComparison = State(initialValue: finance.spendingComparison)
    _appleCardConnection = State(initialValue: finance.appleCardConnection)
    _financeKitSync = State(initialValue: finance.financeKitSync)
    self.analytics = analytics
    notificationManager = devices.notifications
    oauthService = services.oauthService
    mobileSSOService = services.mobileSSOService
    remoteAssistant = finance.remoteAssistant
    financeKitPublisher = finance.financeKitPublisher
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
        firstRun: firstRun,
        financeKitSync: financeKitSync,
        notificationManager: notificationManager,
        remoteAssistant: remoteAssistant,
        transactionHistoryStoreFactory: transactionHistoryStoreFactory,
        localTransactionHistoryStoreFactory: localTransactionHistoryStoreFactory,
        makeAssistantMessageID: { UUID() },
        now: { .now }
      )
      .task { await subscriptionAccess.monitor() }
      .task(id: scenePhase) {
        guard scenePhase == .active else { return }
        await appleCardConnection.refresh()
      }
      .onChange(of: scenePhase) { _, phase in
        if phase == .active {
          Task {
            await subscriptionAccess.refresh()
            #if os(iOS) && FINANCEKIT_ENABLED
            if subscriptionAccess.hasAccess { await financeKitSync.syncOnForeground() }
            #endif
          }
        }
      }
      .onChange(of: connection.status) { _, status in
        if status == .notConnected && connection.isSignedOut {
          firstRun = makeFirstRun()
        }
      }
      .onChange(of: subscriptionAccess.hasAccess, initial: true) { _, allowed in
        if allowed { Task {
          await financeKitPublisher.resumeIfConfigured()
          await financeData.refresh()
          await notificationManager.applicationDidFinishLaunching()
          await notificationManager.didConnect()
        } }
        else {
          if !SureDemoServer.matchesBaseURL(connection.connectedServerURL) {
            financeData.suspendSync()
          }
          if !connection.isDemoServer {
            connection.suspendAuthentication()
            oauthService.cancelAuthentication()
            mobileSSOService.cancelAuthentication()
          }
        }
      }
      .onOpenURL { url in
        guard subscriptionAccess.hasAccess || connection.isDemoServer else { return }
        mobileSSOService.handleOpenURL(url)
      }
    }
  }
}
