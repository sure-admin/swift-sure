import Foundation

struct BudgetCategoryDetailDTO: Decodable {
  var id: UUID
  var budgetID: UUID
  var currency: String
  var displayBudgetedSpending: String
  var displayBudgetedSpendingCents: Int64
  var actualSpending: String
  var actualSpendingCents: Int64
  var category: CategoryDTO

  struct CategoryDTO: Decodable {
    var id: UUID
    var name: String
  }

  func budgetCategoryRecord(
    matching summary: BudgetCategorySummaryDTO,
    budget: BudgetDTO
  ) throws -> BudgetCategoryRecord {
    guard id == summary.id,
          budgetID == summary.budgetID,
          budgetID == budget.id,
          category.id == summary.category.id,
          currency == summary.currency,
          currency == budget.currency,
          let currencyCode = CurrencyCode(currency),
          actualSpendingCents != Int64.min,
          displayBudgetedSpendingCents != Int64.min else {
      throw SureAPIError.decoding
    }

    // Sure's budget serializer represents spending and limits as positive
    // quantities. Normalize unexpected negative quantities once at this DTO
    // boundary so the existing progress UI retains those semantics.
    let spentMinorUnits = actualSpendingCents < 0
      ? -actualSpendingCents
      : actualSpendingCents
    let limitMinorUnits = displayBudgetedSpendingCents < 0
      ? -displayBudgetedSpendingCents
      : displayBudgetedSpendingCents

    return BudgetCategoryRecord(
      id: id,
      budgetID: budgetID,
      categoryID: category.id,
      name: category.name,
      spent: Money(minorUnits: spentMinorUnits, currency: currencyCode),
      limit: Money(minorUnits: limitMinorUnits, currency: currencyCode)
    )
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case budgetID = "budget_id"
    case currency
    case displayBudgetedSpending = "display_budgeted_spending"
    case displayBudgetedSpendingCents = "display_budgeted_spending_cents"
    case actualSpending = "actual_spending"
    case actualSpendingCents = "actual_spending_cents"
    case category
  }
}
