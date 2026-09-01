import SwiftUI

struct AccountsView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.showConnectionSettings) private var showConnectionSettings
  var data: FinanceDataStore
  var appleCardConnection: AppleCardConnectionStore
  var transactionHistoryStoreFactory: TransactionHistoryStoreFactory

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          Text("Accounts")
            .font(.largeTitle.bold())
            .accessibilityAddTraits(.isHeader)
          content
        }
        .frame(maxWidth: 1000)
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.bottom)
        .padding(.top, -9)
      }
      .background(SureTheme.canvas.opacity(0.65))
      .navigationTitle("")
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
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
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 12) {
          HStack(spacing: 12) {
            appleCardIcon
            Text("Apple Card")
              .font(.headline)
          }
          Text(appleCardDetail)
            .font(.subheadline)
            .foregroundStyle(.secondary)
          appleCardAction
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
      } else {
        HStack(spacing: 12) {
          appleCardIcon
          VStack(alignment: .leading, spacing: 2) {
            Text("Apple Card")
              .font(.headline)
            Text(appleCardDetail)
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }

          Spacer(minLength: 4)
          appleCardAction
        }
      }
    }
    .frame(maxWidth: .infinity, minHeight: 65, alignment: .leading)
    .sureCard()
  }

  private var appleCardIcon: some View {
    Image(systemName: "apple.logo")
      .font(.title2)
      .frame(width: 44, height: 44)
      .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
      .accessibilityHidden(true)
  }

  @ViewBuilder
  private var appleCardAction: some View {
    if appleCardConnection.state == .authorized {
      Label("Access granted", systemImage: "checkmark.circle.fill")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.green)
    } else {
      Button("Allow Access", systemImage: "lock.open") {
        Task { await appleCardConnection.connect() }
      }
      .buttonStyle(.borderedProminent)
      .fixedSize(horizontal: true, vertical: false)
      .disabled(
        appleCardConnection.state == .checking
          || appleCardConnection.state == .connecting
          || appleCardConnection.state == .unavailable
      )
      .accessibilityLabel("Allow Apple Card access")
      .accessibilityHint("Requests permission to access financial data in Apple Wallet")
    }
  }

  private var appleCardDetail: String {
    switch appleCardConnection.state {
    case .idle, .checking: "Checking availability…"
    case .ready: "Request financial data access from Wallet."
    case .connecting: "Waiting for Wallet permission…"
    case .authorized: "Wallet access is approved; no account has been added to Sure."
    case .denied: "Access is off. You can enable Finance access in Settings."
    case .failed(let message): message
    case .unavailable: "Unavailable on this device."
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
    let accountColor = accountTypeColor(account.kind)
    return VStack(alignment: .leading, spacing: 14) {
      HStack {
        Image(systemName: account.kind.symbol)
          .frame(width: 42, height: 42)
          .background(accountColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
          .foregroundStyle(accountColor)
          .accessibilityHidden(true)
        Spacer()
        Text(account.kind.rawValue)
          .font(.caption.bold())
          .foregroundStyle(accountColor)
          .padding(.horizontal, 10)
          .padding(.vertical, 5)
          .background(accountColor.opacity(0.14), in: Capsule())
      }

      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 4) {
          Text(account.name)
            .font(.headline)
          Text(account.institution)
            .font(.subheadline)
            .foregroundStyle(.secondary)
          Text(FinanceFormatters.currency(account.balance))
            .font(.title2.bold())
        }
      } else {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
          VStack(alignment: .leading, spacing: 2) {
            Text(account.name)
              .font(.headline)
              .lineLimit(1)
            Text(account.institution)
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
          Spacer(minLength: 4)
          Text(FinanceFormatters.currency(account.balance))
            .font(.title2.bold())
            .fixedSize(horizontal: true, vertical: false)
        }
      }
    }
    .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
    .sureCard()
    .accessibilityElement(children: .combine)
  }

  private func accountTypeColor(_ kind: AccountKind) -> Color {
    switch kind {
    case .cash: .blue
    case .credit: .orange
    case .investment: .purple
    case .property: .teal
    }
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
