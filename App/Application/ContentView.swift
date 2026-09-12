import SwiftUI

struct ContentView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var subscriptionAccess: SubscriptionAccessStore
  var connection: SureConnection
  var analytics: AnalyticsStore
  var financeData: FinanceDataStore
  var spendingComparison: SpendingComparisonStore
  var appleCardConnection: AppleCardConnectionStore
  var notificationManager: any InsightNotificationControlling
  var remoteAssistant: any RemoteAssistantClient
  var makeAssistantServices: () -> AssistantSessionServices
  var transactionHistoryStoreFactory: TransactionHistoryStoreFactory
  var localTransactionHistoryStoreFactory: TransactionHistoryStoreFactory
  var makeAssistantMessageID: () -> UUID
  var now: () -> Date

  @State private var selection: AppSection = .overview
  @State private var showingConnectionSettings = false

  var body: some View {
    appTabs
    .onChange(of: connection.isConfigured, initial: true) { _, configured in
      if !configured && appleCardConnection.isAvailable { selection = .accounts }
    }
    .onChange(of: visibleScreen, initial: true) { _, screen in
      analytics.capture(.screenViewed(screen))
    }
    .environment(\.showConnectionSettings) {
      showingConnectionSettings = true
    }
    .sheet(isPresented: $showingConnectionSettings) {
      ConnectionSettingsView(connection: connection, analytics: analytics)
    }
  }

  private var visibleScreen: UsageScreen {
    if showingConnectionSettings { return .connectionSettings }
    #if os(iOS)
    if !connection.isConfigured && !(appleCardConnection.isAvailable && connection.pendingSSOOnboarding == nil) {
      return connection.pendingSSOOnboarding == nil ? .signIn : .onboarding
    }
    #endif
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
          hasSyncAccess: subscriptionAccess.hasAccess,
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
          services: makeAssistantServices(),
          remoteAssistant: remoteAssistant,
          makeMessageID: makeAssistantMessageID,
          now: now
        )
        .id(connection.sessionGeneration)
      }

      Tab("Accounts", systemImage: "building.columns.fill", value: .accounts) {
        AccountsView(
          data: financeData,
          hasSyncAccess: subscriptionAccess.hasAccess,
          appleCardConnection: appleCardConnection,
          transactionHistoryStoreFactory: transactionHistoryStoreFactory,
          localTransactionHistoryStoreFactory: localTransactionHistoryStoreFactory
        )
        .id(connection.sessionGeneration)
      }

      Tab("Budget", systemImage: "chart.pie.fill", value: .budget) {
        BudgetView(data: financeData, hasSyncAccess: subscriptionAccess.hasAccess)
          .id(connection.sessionGeneration)
      }
    }
    .tabViewStyle(.sidebarAdaptable)
    .simultaneousGesture(
      DragGesture(minimumDistance: 24)
        .onEnded(changeSection)
    )
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
