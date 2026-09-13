import SwiftUI

struct TransactionsView: View {
  @State private var store: TransactionHistoryStore
  @State private var searchText = ""
  @State private var filter: TransactionFilter = .all

  init(store: TransactionHistoryStore) {
    _store = State(initialValue: store)
  }

  private var filteredTransactions: [FinanceTransaction] {
    store.transactions.filter { transaction in
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
    ScrollView {
      Group {
        switch store.state {
        case .idle, .loading:
          loadingView
        case .failed(let message):
          failureView(message: message)
        case .loaded where store.transactions.isEmpty:
          emptyView
        case .loaded where filteredTransactions.isEmpty:
          filteredEmptyView
        case .loaded:
          transactionList
        }
      }
      .frame(maxWidth: 760)
      .frame(maxWidth: .infinity)
      .padding()
    }
    .safeAreaInset(edge: .top) {
      if store.showingDownloadedData {
        Text("Downloaded transactions · Last synchronized window")
          .font(.caption)
          .frame(maxWidth: .infinity)
          .padding(8)
          .background(.regularMaterial)
      }
    }
    .background(SureTheme.canvas.opacity(0.65))
    .navigationTitle(store.scope.navigationTitle)
    .searchable(text: $searchText, prompt: "Merchant or category")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Picker("Filter", selection: $filter) {
          ForEach(TransactionFilter.allCases) { option in
            Text(option.rawValue).tag(option)
          }
        }
        .pickerStyle(.menu)
        .disabled(store.state != .loaded || store.transactions.isEmpty)
      }
    }
    .task {
      if store.state == .idle {
        await store.load()
      }
    }
    .refreshable {
      await store.load()
    }
  }

  private var transactionList: some View {
    LazyVStack(spacing: 0) {
      summary
      ForEach(filteredTransactions) { transaction in
        TransactionRow(transaction: transaction)
        if transaction.id != filteredTransactions.last?.id {
          Divider().padding(.leading, 52)
        }
      }
    }
    .sureCard()
  }

  private var loadingView: some View {
    VStack(spacing: 12) {
      ProgressView()
      Text("Loading transactions…")
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, minHeight: 320)
  }

  private var emptyView: some View {
    ContentUnavailableView {
      Label(store.scope.emptyTitle, systemImage: "list.bullet.rectangle")
    } description: {
      Text(store.scope.emptyDescription)
    }
    .frame(minHeight: 320)
  }

  @ViewBuilder
  private var filteredEmptyView: some View {
    if !searchText.isEmpty {
      ContentUnavailableView.search(text: searchText)
        .frame(minHeight: 320)
    } else {
      ContentUnavailableView(
        filter.emptyTitle,
        systemImage: "line.3.horizontal.decrease.circle",
        description: Text("Try a different filter for \(store.scope.periodLabel.lowercased()).")
      )
      .frame(minHeight: 320)
    }
  }

  private func failureView(message: String) -> some View {
    ContentUnavailableView {
      Label("Couldn’t load transactions", systemImage: "exclamationmark.triangle")
    } description: {
      Text(message)
    } actions: {
      Button("Try again", systemImage: "arrow.clockwise") {
        Task { await store.load() }
      }
      .buttonStyle(.borderedProminent)
    }
    .frame(minHeight: 320)
  }

  private var summary: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(store.scope.periodLabel)
        .font(.subheadline)
        .foregroundStyle(.secondary)
      Text(transactionCountLabel)
        .font(.title.bold())
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.bottom, 14)
  }

  private var transactionCountLabel: String {
    let count = filteredTransactions.count
    return count == 1 ? "1 transaction" : "\(count) transactions"
  }
}

private enum TransactionFilter: String, CaseIterable, Identifiable {
  case all = "All"
  case income = "Income"
  case expenses = "Expenses"

  var id: Self { self }

  var emptyTitle: String {
    switch self {
    case .all: "No transactions"
    case .income: "No income transactions"
    case .expenses: "No expense transactions"
    }
  }
}
