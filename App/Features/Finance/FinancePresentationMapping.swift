import Foundation

enum FinancePresentationMapping {
  static func account(from record: AccountRecord) -> FinanceAccount {
    let kind = accountKind(
      classification: record.classification,
      accountType: record.accountType
    )
    return FinanceAccount(
      id: record.id,
      name: record.name,
      institution: record.institutionName ?? "Institution unavailable",
      kind: kind,
      balance: record.balance,
      tintName: tintName(identifier: record.id)
    )
  }

  static func transaction(from record: TransactionRecord) throws -> FinanceTransaction {
    let kind: TransactionKind = record.classification == .income ? .income : .expense
    let hasExpectedSign = switch kind {
    case .income: record.signedAmount.minorUnits >= 0
    case .expense: record.signedAmount.minorUnits <= 0
    }
    guard hasExpectedSign,
          let magnitude = record.signedAmount.magnitude else {
      throw SureAPIError.decoding
    }
    let category = record.categoryName ?? "Uncategorized"
    return FinanceTransaction(
      id: record.id,
      merchant: record.name,
      category: category,
      symbol: symbol(for: category, kind: kind),
      date: record.date,
      amount: magnitude,
      kind: kind,
      accountID: record.accountID
    )
  }

  static func symbol(for category: String, kind: TransactionKind) -> String {
    if kind == .income { return "arrow.down.left.circle.fill" }
    let lowered = category.lowercased()
    if lowered.contains("food") || lowered.contains("grocer") { return "cart.fill" }
    if lowered.contains("dining") || lowered.contains("restaurant") { return "fork.knife" }
    if lowered.contains("transport") || lowered.contains("auto") { return "car.fill" }
    if lowered.contains("util") { return "bolt.fill" }
    if lowered.contains("shop") { return "bag.fill" }
    if lowered.contains("invest") { return "chart.line.uptrend.xyaxis" }
    return "creditcard.fill"
  }

  private static func accountKind(classification: String, accountType: String?) -> AccountKind {
    let value = "\(classification) \(accountType ?? "")".lowercased()
    if value.contains("invest") { return .investment }
    if value.contains("credit") || value.contains("liabil") { return .credit }
    if value.contains("property") || value.contains("real_estate") { return .property }
    return .cash
  }

  private static func tintName(identifier: UUID) -> String {
    let colors = ["blue", "teal", "purple", "orange"]
    let checksum = identifier.uuidString.utf8.reduce(0) { ($0 + Int($1)) % colors.count }
    return colors[checksum]
  }
}
