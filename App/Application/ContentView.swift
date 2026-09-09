import SwiftUI

struct ContentView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var connection: SureConnection
  var financeData: FinanceDataStore
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
    Group {
      #if os(iOS)
      if connection.isConfigured {
        appTabs
      } else if let onboarding = connection.pendingSSOOnboarding {
        SSOOnboardingHandoffView(
          context: onboarding,
          signInWithPasskey: {
            Task { await connection.signInWithPasskey() }
          },
          goBack: connection.cancelSSOOnboarding
        )
      } else {
        SignInView(
          connection: connection,
          showConnectionSettings: { showingConnectionSettings = true }
        )
      }
      #else
      appTabs
      #endif
    }
    .environment(\.showConnectionSettings) {
      showingConnectionSettings = true
    }
    .sheet(isPresented: $showingConnectionSettings) {
      ConnectionSettingsView(connection: connection)
    }
  }

  private var appTabs: some View {
    TabView(selection: $selection) {
      Tab("Overview", systemImage: "rectangle.grid.2x2.fill", value: .overview) {
        OverviewView(
          data: financeData,
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
          appleCardConnection: appleCardConnection,
          transactionHistoryStoreFactory: transactionHistoryStoreFactory,
          localTransactionHistoryStoreFactory: localTransactionHistoryStoreFactory
        )
        .id(connection.sessionGeneration)
      }

      Tab("Budget", systemImage: "chart.pie.fill", value: .budget) {
        BudgetView(data: financeData)
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
