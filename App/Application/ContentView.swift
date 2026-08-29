import SwiftUI

struct ContentView: View {
  var connection: SureConnection
  var financeData: FinanceDataStore
  var notificationManager: any InsightNotificationControlling
  var remoteAssistant: any RemoteAssistantClient
  var transactionHistoryStoreFactory: TransactionHistoryStoreFactory
  var makeAssistantMessageID: () -> UUID
  var now: () -> Date

  @State private var selection: AppSection = .overview
  @State private var showingConnectionSettings = false

  var body: some View {
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
          transactionHistoryStoreFactory: transactionHistoryStoreFactory
        )
        .id(connection.sessionGeneration)
      }

      Tab("Budget", systemImage: "chart.pie.fill", value: .budget) {
        BudgetView(data: financeData)
          .id(connection.sessionGeneration)
      }
    }
    .tabViewStyle(.sidebarAdaptable)
    .environment(\.showConnectionSettings) {
      showingConnectionSettings = true
    }
    .sheet(isPresented: $showingConnectionSettings) {
      ConnectionSettingsView(connection: connection, financeData: financeData)
    }
  }
}

private enum AppSection: Hashable {
  case overview
  case assistant
  case accounts
  case budget
}
