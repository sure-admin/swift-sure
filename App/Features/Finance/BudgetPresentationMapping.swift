enum BudgetPresentationMapping {
  static func category(from record: BudgetCategoryRecord) -> BudgetCategory {
    BudgetCategory(
      id: record.id,
      name: record.name,
      symbol: FinancePresentationMapping.symbol(for: record.name, kind: .expense),
      spent: record.spent,
      limit: record.limit
    )
  }
}
