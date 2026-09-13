import SwiftUI

struct SpendingComparisonCard: View {
  var store: SpendingComparisonStore
  @State private var expanded = true

  var body: some View {
    DisclosureGroup(isExpanded: $expanded) {
      VStack(alignment: .leading, spacing: 16) {
        if store.source == .wallet {
          Label("Wallet spending · On this device", systemImage: "wallet.bifold")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        if store.source == .sure, store.metadata?.source == .cache {
          Label("Downloaded from Sure", systemImage: "internaldrive")
            .font(.caption)
          if let date = store.metadata?.fetchedAt {
            Text(date, format: .dateTime.month().day().hour().minute()).font(.caption)
          }
        }
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
          Label(store.source == .wallet ? LocalizedStringKey("Wallet spending is unavailable") : LocalizedStringKey("Spending comparison isn’t available yet"), systemImage: "chart.xyaxis.line")
            .font(.headline)
          Text(store.source == .wallet
            ? LocalizedStringKey("Wallet spending is unavailable. Check Wallet access in Accounts.")
            : LocalizedStringKey("This Sure server doesn’t provide the required financial summary."))
            .font(.subheadline)
            .foregroundStyle(.secondary)
        case .noWalletAccounts:
          Text("No shared Wallet accounts. Manage Wallet access in Accounts.")
            .foregroundStyle(.secondary)
        case .multipleCurrencies:
          Text("Wallet accounts use multiple currencies. A combined spending comparison is unavailable without currency conversion.")
            .foregroundStyle(.secondary)
        case .unknownCurrency:
          Text("No Wallet spending or balance currency is available for this period yet.")
            .foregroundStyle(.secondary)
        case .failed:
          Label("Couldn’t load spending comparison", systemImage: "exclamationmark.triangle")
          Button("Try again", systemImage: "arrow.clockwise") {
            Task { await store.refresh() }
          }
          .buttonStyle(.bordered)
        case .loaded(let comparison):
          SpendingComparisonChart(comparison: comparison, isWallet: store.source == .wallet)
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
    .task(id: store.accessIdentity) { await store.refreshIfNeeded() }
  }
}
