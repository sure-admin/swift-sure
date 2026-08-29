import Foundation

struct BudgetCategoryRecord: Equatable, Sendable {
  var id: UUID
  var budgetID: UUID
  var categoryID: UUID
  var name: String
  var spent: Money
  var limit: Money
}
