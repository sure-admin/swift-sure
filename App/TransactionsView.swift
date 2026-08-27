import SwiftUI

struct TransactionsView: View {
  @State private var searchText = ""
  @State private var filter: TransactionFilter = .all

  private var filteredTransactions: [FinanceTransaction] {
    SampleFinanceData.transactions.filter { transaction in
      let matchesSearch = searchText.isEmpty || transaction.merchant.localizedCaseInsensitiveContains(searchText) || transaction.category.localizedCaseInsensitiveContains(searchText)
      let matchesFilter = switch filter {
      case .all: true
      case .income: transaction.kind == .income
      case .expenses: transaction.kind == .expense
      }
      return matchesSearch && matchesFilter
    }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(spacing: 0) {
          summary
          ForEach(filteredTransactions) { transaction in
            TransactionRow(transaction: transaction)
            if transaction.id != filteredTransactions.last?.id {
              Divider().padding(.leading, 52)
            }
          }
        }
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .padding()
        .sureCard()
        .padding()
      }
      .background(SureTheme.canvas.opacity(0.65))
      .navigationTitle("Transactions")
      .searchable(text: $searchText, prompt: "Merchant or category")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Picker("Filter", selection: $filter) {
            ForEach(TransactionFilter.allCases) { option in
              Text(option.rawValue).tag(option)
            }
          }
          .pickerStyle(.menu)
        }
      }
    }
  }

  private var summary: some View {
    HStack {
      VStack(alignment: .leading, spacing: 3) {
        Text("August spending")
          .font(.subheadline)
          .foregroundStyle(.secondary)
        Text(4_982, format: FinanceFormatters.currency)
          .font(.title.bold())
      }
      Spacer()
      Label("12% below July", systemImage: "arrow.down.right")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.green)
    }
    .padding(.bottom, 14)
  }
}

private enum TransactionFilter: String, CaseIterable, Identifiable {
  case all = "All"
  case income = "Income"
  case expenses = "Expenses"

  var id: Self { self }
}
