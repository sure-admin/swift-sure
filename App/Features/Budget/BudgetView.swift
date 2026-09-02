import SwiftUI

struct BudgetView: View {
  @Environment(\.showConnectionSettings) private var showConnectionSettings
  var data: FinanceDataStore

  private var totals: (spent: Money, limit: Money)? {
    let spent = MoneyBreakdown(aggregating: data.budgets.map(\.spent)).singleAmount
    let limit = MoneyBreakdown(aggregating: data.budgets.map(\.limit)).singleAmount
    guard let spent, let limit, spent.currency == limit.currency else { return nil }
    return (spent, limit)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          Text("Budget")
            .font(.largeTitle.bold())
            .accessibilityAddTraits(.isHeader)
          if data.state == .loading {
            ProgressView("Loading budget…")
              .frame(maxWidth: .infinity, minHeight: 260)
          } else if data.state == .needsConnection {
            ContentUnavailableView {
              Label("Connect your Sure account", systemImage: "link.badge.plus")
            } description: {
              Text("Sign in with a passkey or connect with an API key to see your budget.")
            } actions: {
              Button("Connect to Sure", systemImage: "link") {
                showConnectionSettings()
              }
              .buttonStyle(.borderedProminent)
            }
            .frame(minHeight: 260)
          } else if case .failed(let message) = data.state {
            ContentUnavailableView {
              Label("Couldn’t load budget", systemImage: "exclamationmark.triangle")
            } description: {
              Text(message)
            } actions: {
              Button("Try again", systemImage: "arrow.clockwise") {
                Task { await data.refresh() }
              }
              .buttonStyle(.borderedProminent)
            }
            .frame(minHeight: 260)
          } else if let message = data.budgetError, data.budgets.isEmpty {
            ContentUnavailableView {
              Label("Couldn’t load budget", systemImage: "exclamationmark.triangle")
            } description: {
              Text(message)
            } actions: {
              Button("Try again", systemImage: "arrow.clockwise") {
                Task { await data.refresh() }
              }
              .buttonStyle(.borderedProminent)
            }
            .frame(minHeight: 260)
          } else if data.budgets.isEmpty {
            ContentUnavailableView(
              "No current budget",
              systemImage: "chart.pie",
              description: Text("Create a budget in Sure to track it here.")
            )
            .frame(minHeight: 260)
          } else {
            if data.budgetError != nil {
              Label(
                "Budget couldn’t be refreshed. Showing the last loaded values.",
                systemImage: "exclamationmark.triangle"
              )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            budgetHero
            VStack(spacing: 18) {
              ForEach(data.budgets) { category in
                categoryRow(category)
              }
            }
            .sureCard()
          }
        }
        .frame(maxWidth: 760)
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
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button("Connection settings", systemImage: "gearshape") {
            showConnectionSettings()
          }
          .accessibilityHint("Manage your Sure connection")
        }
      }
      .task {
        if data.state == .idle { await data.refresh() }
      }
    }
  }

  private var budgetHero: some View {
    let spent = totals?.spent
    let limit = totals?.limit
    let progress = spent.flatMap { spent in
      limit.map { limit in
        guard limit.decimalValue > 0 else { return 0 }
        return NSDecimalNumber(
          decimal: spent.decimalValue / limit.decimalValue
        ).doubleValue
      }
    } ?? 0
    let available = spent.flatMap { spent in limit?.subtracting(spent) }

    return HStack(spacing: 22) {
      ZStack {
        Circle()
          .stroke(.quaternary, lineWidth: 14)
        Circle()
          .trim(from: 0, to: min(progress, 1))
          .stroke(SureTheme.accent, style: StrokeStyle(lineWidth: 14, lineCap: .round))
          .rotationEffect(.degrees(-90))
        Text(progress, format: .percent.precision(.fractionLength(0)))
          .font(.title2.bold())
      }
      .frame(width: 112, height: 112)
      .accessibilityLabel("\(progress.formatted(.percent.precision(.fractionLength(0)))) of budget spent")
      VStack(alignment: .leading, spacing: 5) {
        Text("Available to spend")
          .foregroundStyle(.secondary)
        Text(available.map(FinanceFormatters.currency) ?? "Unavailable")
          .font(.largeTitle.bold())
        Text("of \(limit.map(FinanceFormatters.currency) ?? "Unavailable") remaining")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .sureCard()
  }

  private func categoryRow(_ category: BudgetCategory) -> some View {
    VStack(spacing: 9) {
      HStack {
        Label(category.name, systemImage: category.symbol)
          .fontWeight(.semibold)
        Spacer()
        Text("\(FinanceFormatters.currency(category.spent)) of \(FinanceFormatters.currency(category.limit))")
          .font(.subheadline.monospacedDigit())
          .foregroundStyle(.secondary)
      }
      ProgressView(value: category.progress)
        .tint(category.progress > 1 ? .red : SureTheme.accent)
        .accessibilityLabel("\(category.name) budget")
        .accessibilityValue(category.progress.formatted(.percent.precision(.fractionLength(0))))
    }
  }
}
