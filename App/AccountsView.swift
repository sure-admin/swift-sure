import SwiftUI

struct AccountsView: View {
  @Environment(\.showConnectionSettings) private var showConnectionSettings
  @State private var data = FinanceDataStore.shared

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
          ForEach(data.accounts) { account in
            accountCard(account)
          }
          addAccountCard
        }
        .frame(maxWidth: 1000)
        .frame(maxWidth: .infinity)
        .padding()
      }
      .background(SureTheme.canvas.opacity(0.65))
      .navigationTitle("Accounts")
      .overlay {
        if data.state == .loading {
          ProgressView("Loading accounts…")
        } else if data.state == .needsConnection {
          ContentUnavailableView {
            Label("Connect your Sure account", systemImage: "link.badge.plus")
          } description: {
            Text("Add your API key to see your accounts.")
          } actions: {
            Button("Connect to Sure", systemImage: "link") {
              showConnectionSettings()
            }
            .buttonStyle(.borderedProminent)
          }
        } else if data.state == .loaded && data.accounts.isEmpty {
          ContentUnavailableView("No accounts", systemImage: "building.columns")
        }
      }
      .task {
        if data.state == .idle { await data.refresh() }
      }
    }
  }

  private func accountCard(_ account: FinanceAccount) -> some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        Image(systemName: account.kind.symbol)
          .frame(width: 42, height: 42)
          .background(SureTheme.accountColor(account.tintName).opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
          .foregroundStyle(SureTheme.accountColor(account.tintName))
        Spacer()
        Image(systemName: "ellipsis")
          .foregroundStyle(.secondary)
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(account.name)
          .font(.headline)
        Text(account.institution)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      HStack(alignment: .firstTextBaseline) {
        Text(account.balance, format: FinanceFormatters.currency)
          .font(.title2.bold())
        Spacer()
        Text(account.kind.rawValue)
          .font(.caption.bold())
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 170, alignment: .leading)
    .sureCard()
    .accessibilityElement(children: .combine)
  }

  private var addAccountCard: some View {
    Button {
      showConnectionSettings()
    } label: {
      VStack(spacing: 12) {
        Image(systemName: "plus")
          .font(.title2.bold())
          .frame(width: 48, height: 48)
          .background(SureTheme.accent, in: Circle())
          .foregroundStyle(SureTheme.ink)
        Text("Add an account")
          .font(.headline)
        Text("Connect or track one manually")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, minHeight: 170)
      .sureCard()
    }
    .buttonStyle(.plain)
  }
}
