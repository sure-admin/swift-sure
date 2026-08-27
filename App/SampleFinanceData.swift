import Foundation

enum SampleFinanceData {
  static let accounts = [
    FinanceAccount(name: "Everyday Checking", institution: "Mercury", kind: .cash, balance: 12_480.32, change: 2.4, tintName: "blue"),
    FinanceAccount(name: "High Yield Savings", institution: "Ally", kind: .cash, balance: 38_220.18, change: 1.2, tintName: "teal"),
    FinanceAccount(name: "Brokerage", institution: "Vanguard", kind: .investment, balance: 94_531.44, change: 5.8, tintName: "purple"),
    FinanceAccount(name: "Travel Card", institution: "Chase", kind: .credit, balance: -2_184.70, change: -8.1, tintName: "orange")
  ]

  static let transactions = [
    FinanceTransaction(merchant: "Payroll", category: "Income", symbol: "briefcase.fill", date: .now, amount: 4_820, kind: .income),
    FinanceTransaction(merchant: "Whole Foods", category: "Groceries", symbol: "cart.fill", date: .now.addingTimeInterval(-7_200), amount: 86.42, kind: .expense),
    FinanceTransaction(merchant: "Blue Bottle", category: "Dining", symbol: "cup.and.saucer.fill", date: .now.addingTimeInterval(-86_400), amount: 7.25, kind: .expense),
    FinanceTransaction(merchant: "Pacific Gas & Electric", category: "Utilities", symbol: "bolt.fill", date: .now.addingTimeInterval(-172_800), amount: 114.36, kind: .expense),
    FinanceTransaction(merchant: "Muni", category: "Transportation", symbol: "tram.fill", date: .now.addingTimeInterval(-259_200), amount: 81, kind: .expense),
    FinanceTransaction(merchant: "Acme Internet", category: "Utilities", symbol: "wifi", date: .now.addingTimeInterval(-345_600), amount: 65, kind: .expense),
    FinanceTransaction(merchant: "Vanguard", category: "Investment", symbol: "chart.line.uptrend.xyaxis", date: .now.addingTimeInterval(-432_000), amount: 750, kind: .expense)
  ]

  static let budgets = [
    BudgetCategory(name: "Groceries", symbol: "cart.fill", spent: 486, limit: 700),
    BudgetCategory(name: "Dining", symbol: "fork.knife", spent: 328, limit: 400),
    BudgetCategory(name: "Transportation", symbol: "car.fill", spent: 164, limit: 350),
    BudgetCategory(name: "Shopping", symbol: "bag.fill", spent: 286, limit: 250)
  ]

  static let balanceHistory = [
    BalancePoint(month: "Mar", value: 126_200),
    BalancePoint(month: "Apr", value: 130_800),
    BalancePoint(month: "May", value: 128_400),
    BalancePoint(month: "Jun", value: 136_900),
    BalancePoint(month: "Jul", value: 139_600),
    BalancePoint(month: "Aug", value: 143_047)
  ]
}
