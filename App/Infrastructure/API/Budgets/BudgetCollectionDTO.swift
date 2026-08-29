struct BudgetCollectionDTO: Decodable {
  var budgets: [BudgetDTO]
  var pagination: PaginationDTO
}
