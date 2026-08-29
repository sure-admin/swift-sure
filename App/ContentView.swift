import SwiftUI

struct ContentView: View {
  var connection: SureConnection
  var financeData: FinanceDataStore
  var notificationManager: any InsightNotificationControlling
  var remoteAssistant: any RemoteAssistantClient
  var transactionHistoryStoreFactory: TransactionHistoryStoreFactory

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
      }

      Tab("Assistant", systemImage: "sparkles", value: .assistant) {
        AssistantView(
          connection: connection,
          financeData: financeData,
          remoteAssistant: remoteAssistant
        )
      }

      Tab("Accounts", systemImage: "building.columns.fill", value: .accounts) {
        AccountsView(
          data: financeData,
          transactionHistoryStoreFactory: transactionHistoryStoreFactory
        )
      }

      Tab("Budget", systemImage: "chart.pie.fill", value: .budget) {
        BudgetView(data: financeData)
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
