import Foundation

struct BudgetCategorySummaryDTO: Decodable {
  var id: UUID
  var budgetID: UUID
  var currency: String
  var category: CategoryDTO

  struct CategoryDTO: Decodable {
    var id: UUID
    var name: String
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case budgetID = "budget_id"
    case currency
    case category
  }
}
