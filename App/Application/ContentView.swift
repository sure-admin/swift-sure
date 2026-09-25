import SwiftUI

struct ContentView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var subscriptionAccess: SubscriptionAccessStore
  var connection: SureConnection
  var analytics: AnalyticsStore
  var financeData: FinanceDataStore
  var spendingComparison: SpendingComparisonStore
  var appleCardConnection: AppleCardConnectionStore
  var firstRun: FirstRunStore?
  var financeKitSync: FinanceKitSyncStore
  var notificationManager: any InsightNotificationControlling
  var remoteAssistant: any RemoteAssistantClient
  var transactionHistoryStoreFactory: TransactionHistoryStoreFactory
  var localTransactionHistoryStoreFactory: TransactionHistoryStoreFactory
  var makeAssistantMessageID: () -> UUID
  var now: () -> Date

  @State private var selection: AppSection = .overview
  @State private var connectionPresentation: ConnectionPresentation?

  var body: some View {
    appTabs
    .onChange(of: connection.isConfigured, initial: true) { _, configured in
      if connection.allowsWalletPreview && !configured && appleCardConnection.isAvailable { selection = .accounts }
    }
    .onChange(of: connection.status) { _, status in
      if status == .notConnected && connection.isSignedOut {
        connectionPresentation = nil
      } else if status == .connected && connectionPresentation == .demoSignIn {
        connectionPresentation = nil
      }
    }
    .onChange(of: visibleScreen, initial: true) { _, screen in
      analytics.capture(.screenViewed(screen))
    }
    .environment(\.showConnectionSettings) {
      connectionPresentation = .settings
    }
    .sheet(item: $connectionPresentation) { presentation in
      switch presentation {
      case .settings:
        ConnectionSettingsView(subscriptionAccess: subscriptionAccess, connection: connection, analytics: analytics,
          financeKitSync: financeKitSync, wallet: appleCardConnection)
      case .demoSignIn:
        SignInView(subscriptionAccess: subscriptionAccess, connection: connection,
          showConnectionSettings: { connectionPresentation = .settings })
      }
    }
    #if os(iOS)
    .fullScreenCover(isPresented: .constant(firstRun?.isFinished == false), onDismiss: routeAfterFirstRun) {
      if let firstRun { FirstRunView(store: firstRun) }
    }
    #endif
  }

  // Routes once the cover has dismissed, so a follow-up sheet can present.
  private func routeAfterFirstRun() {
    switch firstRun?.outcome {
    case .walletConnected:
      // Overview shows the local Wallet spending comparison: the "wow" moment.
      selection = .overview
    case .exploreDemo:
      connection.prepareDemoSignIn()
      connectionPresentation = .demoSignIn
    case nil:
      break
    }
  }

  private var visibleScreen: UsageScreen {
    switch connectionPresentation {
    case .settings: return .connectionSettings
    case .demoSignIn: return .signIn
    case nil: break
    }
    switch selection {
    case .overview: return .overview
    case .assistant: return .assistant
    case .accounts: return .accounts
    case .budget: return .budget
    }
  }

  private var appTabs: some View {
    TabView(selection: $selection) {
      Tab("Overview", systemImage: "rectangle.grid.2x2.fill", value: .overview) {
        OverviewView(
          data: financeData,
          hasSyncAccess: hasBackendAccess,
          spendingComparison: spendingComparison,
          refreshWalletAccess: { await appleCardConnection.refresh() },
          notificationManager: notificationManager,
          transactionHistoryStoreFactory: transactionHistoryStoreFactory
        )
        .id(connection.sessionGeneration)
      }

      Tab("Assistant", systemImage: "sparkles", value: .assistant) {
        AssistantView(
          connection: connection,
          financeData: financeData,
          remoteAssistant: remoteAssistant,
          makeMessageID: makeAssistantMessageID,
          now: now
        )
        .id(connection.sessionGeneration)
      }

      Tab("Accounts", systemImage: "building.columns.fill", value: .accounts) {
        AccountsView(
          data: financeData,
          hasSyncAccess: hasBackendAccess,
          appleCardConnection: appleCardConnection,
          transactionHistoryStoreFactory: transactionHistoryStoreFactory,
          localTransactionHistoryStoreFactory: localTransactionHistoryStoreFactory
        )
        .id(connection.sessionGeneration)
      }

      Tab("Budget", systemImage: "chart.pie.fill", value: .budget) {
        BudgetView(data: financeData, hasSyncAccess: hasBackendAccess)
          .id(connection.sessionGeneration)
      }
    }
    .tabViewStyle(.sidebarAdaptable)
    .simultaneousGesture(
      DragGesture(minimumDistance: 24)
        .onEnded(changeSection)
    )
  }

  private var hasBackendAccess: Bool {
    subscriptionAccess.gate.isAllowed(for: connection.connectedServerURL)
  }

  private func changeSection(_ value: DragGesture.Value) {
    let horizontalDistance = value.predictedEndTranslation.width
    let verticalDistance = value.predictedEndTranslation.height
    guard abs(horizontalDistance) > 60,
          abs(horizontalDistance) > abs(verticalDistance) * 1.25 else {
      return
    }

    let destination = selection.moving(by: horizontalDistance < 0 ? 1 : -1)
    guard destination != selection else { return }
    withAnimation(reduceMotion ? nil : .snappy) {
      selection = destination
    }
  }
}

private enum ConnectionPresentation: String, Identifiable {
  case settings, demoSignIn
  var id: Self { self }
}
