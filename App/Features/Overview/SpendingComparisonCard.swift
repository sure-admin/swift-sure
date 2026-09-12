import SwiftUI

struct SpendingComparisonCard: View {
  var store: SpendingComparisonStore
  @State private var expanded = true

  var body: some View {
    DisclosureGroup(isExpanded: $expanded) {
      VStack(alignment: .leading, spacing: 16) {
        if let month = store.selectedMonth {
          Picker("Spending month", selection: Binding(
            get: { month },
            set: { month in Task { await store.select(month) } }
          )) {
            ForEach(store.months, id: \.self) { month in
              Text(FinanceFormatters.monthAndYear(month.start, calendar: Calendar(identifier: .gregorian)))
                .tag(month)
            }
          }
          .pickerStyle(.menu)
          .frame(maxWidth: .infinity, alignment: .trailing)
        }

        switch store.state {
        case .idle, .loading:
          HStack {
            ProgressView()
            Text("Loading spending comparison…")
              .foregroundStyle(.secondary)
          }
        case .unavailable:
          Label("Spending comparison isn’t available yet", systemImage: "chart.xyaxis.line")
            .font(.headline)
          Text("The spending totals used by Sure’s web dashboard aren’t available to this app yet.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        case .failed:
          Label("Couldn’t load spending comparison", systemImage: "exclamationmark.triangle")
          Button("Try again", systemImage: "arrow.clockwise") {
            Task { await store.refresh() }
          }
          .buttonStyle(.bordered)
        case .loaded(let comparison):
          SpendingComparisonChart(comparison: comparison)
            .id(comparison.month)
        }
      }
      .padding(.top, 12)
      .frame(maxWidth: .infinity, alignment: .leading)
    } label: {
      Text("Spending")
        .font(.title3.bold())
        .accessibilityAddTraits(.isHeader)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .sureCard()
    .task { await store.refreshIfNeeded() }
  }
}
