import SwiftUI

struct AccountsView: View {
  @Environment(\.showConnectionSettings) private var showConnectionSettings
  var data: FinanceDataStore
  var appleCardConnection: AppleCardConnectionStore
  var transactionHistoryStoreFactory: TransactionHistoryStoreFactory

  var body: some View {
    NavigationStack {
      ScrollView {
        content
        .frame(maxWidth: 1000)
        .frame(maxWidth: .infinity)
        .padding()
      }
      .background(SureTheme.canvas.opacity(0.65))
      .navigationTitle("Accounts")
      .task {
        if data.state == .idle { await data.refresh() }
        if appleCardConnection.state == .idle { await appleCardConnection.refresh() }
      }
    }
  }

  @ViewBuilder
  private var content: some View {
    switch data.state {
    case .idle, .loading:
      ProgressView("Loading accounts…")
        .frame(minHeight: 420)
    case .needsConnection:
      ContentUnavailableView {
        Label("Connect your Sure account", systemImage: "link.badge.plus")
      } description: {
        Text("Sign in with a passkey or connect with an API key to see your accounts.")
      } actions: {
        Button("Connect to Sure", systemImage: "link") {
          showConnectionSettings()
        }
        .buttonStyle(.borderedProminent)
      }
      .frame(minHeight: 420)
    case .failed(let message):
      ContentUnavailableView {
        Label("Couldn’t load accounts", systemImage: "exclamationmark.triangle")
      } description: {
        Text(message)
      } actions: {
        Button("Try again", systemImage: "arrow.clockwise") {
          Task { await data.refresh() }
        }
        .buttonStyle(.borderedProminent)
        Button("Connection settings", systemImage: "gearshape") {
          showConnectionSettings()
        }
        .buttonStyle(.bordered)
      }
      .frame(minHeight: 420)
    case .loaded:
      if let message = data.accountsError, data.accounts.isEmpty {
        ContentUnavailableView {
          Label("Couldn’t load accounts", systemImage: "exclamationmark.triangle")
        } description: {
          Text(message)
        } actions: {
          Button("Try again", systemImage: "arrow.clockwise") {
            Task { await data.refresh() }
          }
          .buttonStyle(.borderedProminent)
        }
        .frame(minHeight: 420)
      } else {
        VStack(spacing: 16) {
          if data.accountsError != nil {
            Label("Accounts couldn’t be refreshed. Showing the last loaded data.", systemImage: "exclamationmark.triangle")
              .font(.footnote)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
            appleCardCard
            ForEach(data.accounts) { account in
              accountLink(account)
            }
            addAccountCard
          }
        }
      }
    }
  }

  private var appleCardCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 12) {
        Image(systemName: "apple.logo")
          .font(.title2)
          .frame(width: 44, height: 44)
          .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text("Apple Card")
            .font(.headline)
          Text(appleCardDetail)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        Spacer()
      }

      if appleCardConnection.state == .connected {
        Label("Connected on this device", systemImage: "checkmark.circle.fill")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.green)
      } else {
        Button("Connect Apple Card", systemImage: "link") {
          Task { await appleCardConnection.connect() }
        }
        .buttonStyle(.borderedProminent)
        .disabled(
          appleCardConnection.state == .checking
            || appleCardConnection.state == .connecting
            || appleCardConnection.state == .unavailable
        )
        .accessibilityHint("Requests permission to access financial data in Apple Wallet")
      }
    }
    .frame(maxWidth: .infinity, minHeight: 170, alignment: .leading)
    .sureCard()
  }

  private var appleCardDetail: String {
    switch appleCardConnection.state {
    case .idle, .checking: "Checking availability…"
    case .ready: "Securely access your Apple Card data from Wallet."
    case .connecting: "Waiting for Wallet permission…"
    case .connected: "Sure can access Apple Card data you approve in Wallet."
    case .denied: "Access is off. You can enable Finance access in Settings."
    case .failed(let message): message
    case .unavailable: "Apple Card isn’t available on this device."
    }
  }

  @ViewBuilder
  private func accountLink(_ account: FinanceAccount) -> some View {
    NavigationLink {
      TransactionsView(
        store: transactionHistoryStoreFactory.makeStore(
          for: .account(id: account.id, name: account.name)
        )
      )
    } label: {
      accountCard(account)
    }
    .buttonStyle(.plain)
    .accessibilityHint("Shows transactions from the last 31 days")
  }

  private func accountCard(_ account: FinanceAccount) -> some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        Image(systemName: account.kind.symbol)
          .frame(width: 42, height: 42)
          .background(SureTheme.accountColor(account.tintName).opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
          .foregroundStyle(SureTheme.accountColor(account.tintName))
          .accessibilityHidden(true)
        Spacer()
        Image(systemName: "chevron.right")
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(account.name)
          .font(.headline)
        Text(account.institution)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      HStack(alignment: .firstTextBaseline) {
        Text(FinanceFormatters.currency(account.balance))
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
        Text("Connection settings")
          .font(.headline)
        Text("Manage your Sure connection")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, minHeight: 170)
      .sureCard()
    }
    .buttonStyle(.plain)
  }
}
