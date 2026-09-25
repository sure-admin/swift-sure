import Foundation

struct FinanceAccount: Equatable, Identifiable {
  var id: UUID
  var name: String
  var institution: String
  var kind: AccountKind
  var balance: Money
  var tintName: String
  var isLiability: Bool? = nil
  var walletSourceAccountID: UUID? = nil

  var displayInstitution: String { walletSourceAccountID == nil ? institution : "Apple Wallet" }

  /// Sure stores debt as positive liabilities and credit balances as negative.
  /// Preserve that wire value; invert once for the signed account-card display.
  var displayBalance: DecimalMoney {
    let liability = isLiability ?? (kind == .credit)
    return DecimalMoney(amount: liability ? -balance.decimalValue : balance.decimalValue,
      currency: balance.currency)
  }
}
