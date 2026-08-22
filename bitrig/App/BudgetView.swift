import SwiftUI

struct BudgetView: View {
  @State private var data = FinanceDataStore.shared

  private var spent: Double { data.budgets.reduce(0) { $0 + $1.spent } }
  private var limit: Double { data.budgets.reduce(0) { $0 + $1.limit } }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 18) {
          if data.state == .loading {
            ProgressView("Loading budget…")
              .frame(maxWidth: .infinity, minHeight: 260)
          } else if data.budgets.isEmpty {
            ContentUnavailableView(
              "No current budget",
              systemImage: "chart.pie",
              description: Text("Create a budget in Sure to track it here.")
            )
            .frame(minHeight: 260)
          } else {
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
        .padding()
      }
      .background(SureTheme.canvas.opacity(0.65))
      .navigationTitle("August budget")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button("Edit budget", systemImage: "slider.horizontal.3") { }
        }
      }
      .task {
        if data.state == .idle { await data.refresh() }
      }
    }
  }

  private var budgetHero: some View {
    HStack(spacing: 22) {
      ZStack {
        Circle()
          .stroke(.quaternary, lineWidth: 14)
        Circle()
          .trim(from: 0, to: limit > 0 ? min(spent / limit, 1) : 0)
          .stroke(SureTheme.accent, style: StrokeStyle(lineWidth: 14, lineCap: .round))
          .rotationEffect(.degrees(-90))
        Text(limit > 0 ? spent / limit : 0, format: .percent.precision(.fractionLength(0)))
          .font(.title2.bold())
      }
      .frame(width: 112, height: 112)
      .accessibilityLabel("67 percent of budget spent")
      VStack(alignment: .leading, spacing: 5) {
        Text("Available to spend")
          .foregroundStyle(.secondary)
        Text(limit - spent, format: FinanceFormatters.currency)
          .font(.largeTitle.bold())
        Text("of \(limit.formatted(FinanceFormatters.currency)) remaining")
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
        Text("\(category.spent.formatted(FinanceFormatters.currency)) of \(category.limit.formatted(FinanceFormatters.currency))")
          .font(.subheadline.monospacedDigit())
          .foregroundStyle(.secondary)
      }
      ProgressView(value: category.spent, total: category.limit)
        .tint(category.progress > 1 ? .red : SureTheme.accent)
        .accessibilityLabel("\(category.name) budget")
        .accessibilityValue(category.progress.formatted(.percent.precision(.fractionLength(0))))
    }
  }
}
