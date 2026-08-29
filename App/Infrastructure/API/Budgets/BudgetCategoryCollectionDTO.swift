struct BudgetCategoryCollectionDTO: Decodable {
  var budgetCategories: [BudgetCategorySummaryDTO]
  var pagination: PaginationDTO

  private enum CodingKeys: String, CodingKey {
    case budgetCategories = "budget_categories"
    case pagination
  }
}
