import Charts
import SwiftUI

struct OverviewView: View {
  @State private var data = FinanceDataStore.shared

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          welcomeHeader
          content
        }
        .frame(maxWidth: 1100, alignment: .leading)
        .frame(maxWidth: .infinity)
        .padding()
      }
      .background(SureTheme.canvas.opacity(0.65))
      .navigationTitle("Overview")
      .toolbar {
        ToolbarItemGroup(placement: .primaryAction) {
          Button("Refresh", systemImage: "arrow.clockwise") {
            Task { await data.refresh() }
          }
          .disabled(data.state == .loading)
          Button("Add", systemImage: "plus") { }
            .accessibilityHint("Add an account or transaction")
        }
      }
      .task {
        if data.state == .idle || data.state == .needsConnection {
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
      ContentUnavailableView(
        "Connect your Sure account",
        systemImage: "link.badge.plus",
        description: Text("Open Assistant connection settings to add your API key.")
      )
    case .failed(let message):
      ContentUnavailableView(
        "Couldn’t load Sure",
        systemImage: "exclamationmark.triangle",
        description: Text(message)
      )
    case .loaded:
      InsightCard(
        insights: data.insights,
        isLoading: data.isLoadingInsights,
        errorMessage: data.insightError
      )
      netWorthCard
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

  private var welcomeHeader: some View {
    HStack(alignment: .bottom) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Good afternoon")
          .font(.title.bold())
        Text("Here’s your complete financial picture.")
          .foregroundStyle(.secondary)
      }
      Spacer()
      if let lastUpdated = data.lastUpdated {
        Text("Updated \(lastUpdated, format: .relative(presentation: .named))")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .combine)
  }

  private var netWorthCard: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Net worth")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
          Text(data.netWorth, format: FinanceFormatters.currency)
            .font(.system(.largeTitle, design: .rounded, weight: .bold))
            .contentTransition(.numericText())
        }
        Spacer()
        Text("LIVE")
          .font(.caption2.bold())
          .padding(.horizontal, 9)
          .padding(.vertical, 5)
          .background(SureTheme.accent, in: Capsule())
          .foregroundStyle(SureTheme.ink)
      }

      if !data.accounts.isEmpty {
        Chart(topAccounts) { account in
          BarMark(
            x: .value("Balance", abs(account.balance)),
            y: .value("Account", account.name)
          )
          .foregroundStyle(SureTheme.accountColor(account.tintName))
          .cornerRadius(5)
        }
        .chartXAxis(.hidden)
        .frame(minHeight: 150)
        .accessibilityLabel("Account balances contributing to net worth")
        if data.accounts.count > topAccounts.count {
          Text("Showing the \(topAccounts.count) largest of \(data.accounts.count) accounts")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
    .sureCard()
  }

  private var spendingCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(data.reportingPeriodLabel)
        .font(.title3.bold())
      HStack(spacing: 18) {
        metric(title: "Income", value: data.periodIncome, color: .green)
        metric(title: "Spent", value: data.periodSpending, color: .orange)
      }
      if data.periodIncome > 0 {
        Divider()
        HStack {
          Label("Savings rate", systemImage: "leaf.fill")
          Spacer()
          Text(max(0, (data.periodIncome - data.periodSpending) / data.periodIncome), format: .percent.precision(.fractionLength(0)))
            .fontWeight(.bold)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .sureCard()
  }

  private var recentCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Recent activity")
        .font(.title3.bold())
      if data.transactions.isEmpty {
        Text("No recent transactions")
          .foregroundStyle(.secondary)
      } else {
        ForEach(data.transactions.prefix(3)) { transaction in
          TransactionRow(transaction: transaction)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .sureCard()
  }

  private func metric(title: String, value: Double, color: Color) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(value, format: FinanceFormatters.compactCurrency)
        .font(.title2.bold())
      Capsule().fill(color).frame(width: 36, height: 4)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var topAccounts: [FinanceAccount] {
    Array(data.accounts.sorted { abs($0.balance) > abs($1.balance) }.prefix(5))
  }
}
