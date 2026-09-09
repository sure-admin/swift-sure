import Foundation

struct LocalFinancialTransactionMapper {
  func map(
    id: UUID,
    accountID: UUID,
    merchantName: String?,
    description: String,
    category: String,
    date: Date,
    amount: Decimal,
    currencyCode: String,
    isCredit: Bool,
    calendar: Calendar
  ) throws -> FinanceTransaction {
    let signedAmount = try LocalFinancialBalanceMapper().map(
      amount: amount,
      currencyCode: currencyCode,
      direction: isCredit ? .credit : .debit
    )
    guard let magnitude = signedAmount.magnitude else {
      throw LocalFinancialBalanceMapper.MappingError.invalidAmount
    }
    let kind: TransactionKind = isCredit ? .income : .expense
    return FinanceTransaction(
      id: id,
      merchant: merchantName ?? description,
      category: category,
      symbol: symbol(for: category, kind: kind),
      date: try LocalDate(date, in: calendar),
      amount: magnitude,
      kind: kind,
      accountID: accountID
    )
  }

  private func symbol(for category: String, kind: TransactionKind) -> String {
    if kind == .income { return "arrow.down.left.circle.fill" }
    let lowered = category.lowercased()
    if lowered.contains("deposit") { return "banknote.fill" }
    if lowered.contains("transfer") { return "arrow.left.arrow.right" }
    if lowered.contains("fee") || lowered.contains("interest") { return "percent" }
    if lowered.contains("atm") || lowered.contains("withdrawal") { return "banknote" }
    return "creditcard.fill"
  }
}
