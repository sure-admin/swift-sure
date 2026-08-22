import Charts
import SwiftUI

struct OverviewView: View {
  private var netWorth: Double {
    SampleFinanceData.accounts.reduce(0) { $0 + $1.balance }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          welcomeHeader
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
        .frame(maxWidth: 1100, alignment: .leading)
        .frame(maxWidth: .infinity)
        .padding()
      }
      .background(SureTheme.canvas.opacity(0.65))
      .navigationTitle("Overview")
      .toolbar {
        ToolbarItemGroup(placement: .primaryAction) {
          Button("Search", systemImage: "magnifyingglass") { }
            .accessibilityHint("Search your finances")
          Button("Add", systemImage: "plus") { }
            .accessibilityHint("Add an account or transaction")
        }
      }
    }
  }

  private var welcomeHeader: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Good afternoon")
        .font(.title.bold())
      Text("Here’s your complete financial picture.")
        .foregroundStyle(.secondary)
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
          Text(netWorth, format: FinanceFormatters.currency)
            .font(.system(.largeTitle, design: .rounded, weight: .bold))
            .contentTransition(.numericText())
          Label("$7,420 this month", systemImage: "arrow.up.right")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.green)
        }
        Spacer()
        Text("LIVE")
          .font(.caption2.bold())
          .padding(.horizontal, 9)
          .padding(.vertical, 5)
          .background(SureTheme.accent, in: Capsule())
          .foregroundStyle(SureTheme.ink)
      }

      Chart(SampleFinanceData.balanceHistory) { point in
        AreaMark(
          x: .value("Month", point.month),
          y: .value("Balance", point.value)
        )
        .foregroundStyle(
          .linearGradient(colors: [SureTheme.accent.opacity(0.55), SureTheme.accent.opacity(0.03)], startPoint: .top, endPoint: .bottom)
        )
        LineMark(
          x: .value("Month", point.month),
          y: .value("Balance", point.value)
        )
        .foregroundStyle(SureTheme.ink)
        .lineStyle(.init(lineWidth: 3, lineCap: .round, lineJoin: .round))
        .symbol(Circle())
      }
      .chartYAxis(.hidden)
      .chartXAxis {
        AxisMarks { _ in
          AxisValueLabel()
          AxisGridLine().foregroundStyle(.clear)
        }
      }
      .frame(height: 190)
      .accessibilityLabel("Net worth increased from 126,200 dollars in March to 143,047 dollars in August")
    }
    .sureCard()
  }

  private var spendingCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("This month")
        .font(.title3.bold())
      HStack(spacing: 18) {
        metric(title: "Income", value: 8_460, color: .green)
        metric(title: "Spent", value: 4_982, color: .orange)
      }
      Divider()
      HStack {
        Label("Savings rate", systemImage: "leaf.fill")
        Spacer()
        Text("41%")
          .fontWeight(.bold)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .sureCard()
  }

  private var recentCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Recent activity")
          .font(.title3.bold())
        Spacer()
        Button("See all") { }
      }
      ForEach(SampleFinanceData.transactions.prefix(3)) { transaction in
        TransactionRow(transaction: transaction)
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
      Capsule()
        .fill(color)
        .frame(width: 36, height: 4)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
