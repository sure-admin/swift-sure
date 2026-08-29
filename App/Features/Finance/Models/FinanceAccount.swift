import Foundation

struct FinanceAccount: Identifiable {
  var id: UUID
  var name: String
  var institution: String
  var kind: AccountKind
  var balance: Money
  var tintName: String
}
