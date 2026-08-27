import SwiftUI

struct ContentView: View {
  @State private var selection: AppSection = .overview
  @State private var showingConnectionSettings = false

  var body: some View {
    TabView(selection: $selection) {
      Tab("Overview", systemImage: "rectangle.grid.2x2.fill", value: .overview) {
        OverviewView()
      }

      Tab("Assistant", systemImage: "sparkles", value: .assistant) {
        AssistantView()
      }

      Tab("Accounts", systemImage: "building.columns.fill", value: .accounts) {
        AccountsView()
      }

      Tab("Budget", systemImage: "chart.pie.fill", value: .budget) {
        BudgetView()
      }
    }
    .tabViewStyle(.sidebarAdaptable)
    .environment(\.showConnectionSettings) {
      showingConnectionSettings = true
    }
    .sheet(isPresented: $showingConnectionSettings) {
      ConnectionSettingsView()
    }
  }
}

private enum AppSection: Hashable {
  case overview
  case assistant
  case accounts
  case budget
}
