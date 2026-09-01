import Charts
import SwiftUI

struct OverviewView: View {
  private static let cardContentInset: CGFloat = 20
  private static let statusColumnWidth: CGFloat = 56

  @Environment(\.showConnectionSettings) private var showConnectionSettings
  var data: FinanceDataStore
  var notificationManager: any InsightNotificationControlling
  var transactionHistoryStoreFactory: TransactionHistoryStoreFactory

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          overviewHeader
          content
        }
        .frame(maxWidth: 1100, alignment: .leading)
        .frame(maxWidth: .infinity)
        .padding()
      }
      .background(SureTheme.canvas.opacity(0.65))
      .navigationTitle("")
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItemGroup(placement: .primaryAction) {
          Button("Refresh", systemImage: "arrow.clockwise") {
            Task { await data.refresh() }
          }
          .disabled(data.state == .loading)
          Button("Connection settings", systemImage: "gearshape") {
            showConnectionSettings()
          }
          .accessibilityHint("Manage your Sure connection")
        }
      }
      .task {
        if data.state == .idle {
          await data.refresh()
        }
      }
      .refreshable { await data.refresh() }
    }
  }

  @ViewBuilder
  private var content: some View {
    switch data.state {
    case .idle, .loading:
      loadingView
    case .needsConnection:
      ContentUnavailableView {
        Label("Connect your Sure account", systemImage: "link.badge.plus")
      } description: {
        Text("Sign in with a passkey or connect with an API key to load your finances.")
      } actions: {
        Button("Connect to Sure", systemImage: "link") {
          showConnectionSettings()
        }
        .buttonStyle(.borderedProminent)
      }
    case .failed(let message):
      ContentUnavailableView {
        Label("Couldn’t load Sure", systemImage: "exclamationmark.triangle")
      } description: {
        Text(message)
      } actions: {
        Button("Connection settings", systemImage: "gearshape") {
          showConnectionSettings()
        }
        .buttonStyle(.bordered)
      }
    case .loaded:
      InsightCard(
        insights: data.insights,
        isLoading: data.isLoadingInsights,
        errorMessage: data.insightError,
        notificationManager: notificationManager,
        statusColumnWidth: Self.statusColumnWidth
      )
      if (data.accountsError != nil && !data.accounts.isEmpty)
          || (data.transactionsError != nil && !data.transactions.isEmpty) {
        Label(
          "Some data couldn’t be refreshed. Showing the last loaded values.",
          systemImage: "exclamationmark.triangle"
        )
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      ViewThatFits {
        HStack(alignment: .top, spacing: 18) {
          spendingCard
          recentCard
        }
        VStack(spacing: 18) {
          spendingCard
          recentCard
        }
      }
      netWorthCard
    }
  }

  private var loadingView: some View {
    VStack(spacing: 12) {
      ProgressView()
      Text("Loading your Sure finances…")
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, minHeight: 320)
  }

  private var overviewHeader: some View {
    HStack(alignment: .lastTextBaseline, spacing: 12) {
      Text("Overview")
        .font(.largeTitle.bold())
        .accessibilityAddTraits(.isHeader)
      Spacer()
      if let lastUpdated = data.lastUpdated {
        Text("Updated \(lastUpdated, format: .relative(presentation: .named))")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: true, vertical: false)
          .frame(width: Self.statusColumnWidth)
      }
    }
    .padding(.trailing, Self.cardContentInset)
  }

  private var netWorthCard: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 4) {
          Label("Net Worth", systemImage: "chart.line.uptrend.xyaxis")
            .font(.title3.bold())
          Text(data.netWorth.map(FinanceFormatters.currency) ?? "Unavailable")
            .font(.system(.largeTitle, design: .rounded, weight: .bold))
            .contentTransition(.numericText())
          if data.balanceSheetError != nil {
            Label("Net worth couldn’t be refreshed", systemImage: "exclamationmark.triangle")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        Spacer()
        if data.balanceSheetError == nil {
          Text("LIVE")
            .font(.caption2.bold())
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(SureTheme.highlight, in: Capsule())
            .foregroundStyle(SureTheme.ink)
            .frame(width: Self.statusColumnWidth)
        }
      }

      if !data.accounts.isEmpty {
        if let chartAccounts {
          Chart(chartAccounts) { account in
            BarMark(
              x: .value(
                "Balance",
                NSDecimalNumber(decimal: account.balance.decimalValue.magnitude).doubleValue
              ),
              y: .value("Account", account.name)
            )
            .foregroundStyle(SureTheme.accountColor(account.tintName))
            .cornerRadius(5)
          }
          .chartXAxis(.hidden)
          .frame(minHeight: 150)
          .accessibilityLabel("Account balances in \(data.balanceSheet?.currency.rawValue ?? "the reporting currency")")
          if data.accounts.count > chartAccounts.count {
            Text("Showing the \(chartAccounts.count) largest of \(data.accounts.count) accounts")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        } else {
          Text("Account balances use multiple currencies. Open Accounts to see each native balance.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      } else if data.accountsError != nil {
        Text("The account breakdown is currently unavailable.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .sureCard()
  }

  private var spendingCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(data.reportingPeriodLabel)
        .font(.title3.bold())
      if data.transactionsError != nil && data.transactions.isEmpty {
        Label("Spending activity is currently unavailable", systemImage: "exclamationmark.triangle")
          .foregroundStyle(.secondary)
      } else {
        HStack(spacing: 18) {
          metric(title: "Income", value: data.periodIncome, color: .green)
          metric(title: "Spent", value: data.periodSpending, color: .orange)
        }
        if let savingsRate = data.savingsRate {
          Divider()
          HStack {
            Label("Savings rate", systemImage: "leaf.fill")
            Spacer()
            Text(savingsRate, format: .percent.precision(.fractionLength(0)))
              .fontWeight(.bold)
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .sureCard()
  }

  private var recentCard: some View {
    let recentTransactions = data.recentActivityTransactions
    return VStack(alignment: .leading, spacing: 10) {
      NavigationLink {
        TransactionsView(
          store: transactionHistoryStoreFactory.makeStore(for: .recentActivity)
        )
      } label: {
        HStack {
          Text("Recent activity")
            .font(.title3.bold())
          Spacer()
          Image(systemName: "chevron.right")
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
      }
      .buttonStyle(.plain)
      .accessibilityHint("Shows activity from the last 7 days")

      if data.transactionsError != nil && recentTransactions.isEmpty {
        Text("Recent activity is currently unavailable")
          .foregroundStyle(.secondary)
      } else if recentTransactions.isEmpty {
        Text("No activity in the last 7 days")
          .foregroundStyle(.secondary)
      } else {
        ForEach(recentTransactions.prefix(3)) { transaction in
          TransactionRow(transaction: transaction)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .sureCard()
  }

  private func metric(title: String, value: MoneyBreakdown, color: Color) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(FinanceFormatters.currency(
        value,
        compact: true,
        zeroCurrency: data.balanceSheet?.currency
      ))
        .font(.title2.bold())
      Capsule().fill(color).frame(width: 36, height: 4)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var chartAccounts: [FinanceAccount]? {
    guard let reportingCurrency = data.balanceSheet?.currency,
          data.accounts.allSatisfy({ $0.balance.currency == reportingCurrency }) else {
      return nil
    }
    return Array(
      data.accounts.sorted {
        $0.balance.decimalValue.magnitude > $1.balance.decimalValue.magnitude
      }
      .prefix(5)
    )
  }
}
