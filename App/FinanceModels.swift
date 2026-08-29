import Foundation

enum AccountKind: String, CaseIterable, Identifiable {
  case cash = "Cash"
  case credit = "Credit"
  case investment = "Investment"
  case property = "Property"

  var id: Self { self }

  var symbol: String {
    switch self {
    case .cash: "building.columns.fill"
    case .credit: "creditcard.fill"
    case .investment: "chart.line.uptrend.xyaxis"
    case .property: "house.fill"
    }
  }
}

struct FinanceAccount: Identifiable {
  var id = UUID().uuidString
  var name: String
  var institution: String
  var kind: AccountKind
  var balance: Double
  var change: Double
  var tintName: String
  var currencyCode: String? = nil
}

enum TransactionKind {
  case income
  case expense
}

struct FinanceTransaction: Identifiable {
  var id = UUID().uuidString
  var merchant: String
  var category: String
  var symbol: String
  var date: Date
  var amount: Double
  var kind: TransactionKind
  var accountID: String? = nil
  var currencyCode: String? = nil
}

struct BudgetCategory: Identifiable {
  var id = UUID().uuidString
  var name: String
  var symbol: String
  var spent: Double
  var limit: Double

  var progress: Double {
    guard limit > 0 else { return 0 }
    return spent / limit
  }
}

struct BalancePoint: Identifiable {
  var id = UUID()
  var month: String
  var value: Double
}
