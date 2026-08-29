import Foundation

struct BudgetDTO: Decodable {
  var id: UUID
  var startDate: LocalDate
  var endDate: LocalDate
  var name: String
  var currency: String
  var initialized: Bool
  var current: Bool
  var allocatedSpending: String
  var allocatedSpendingCents: Int64
  var createdAt: Date
  var updatedAt: Date

  private enum CodingKeys: String, CodingKey {
    case id
    case startDate = "start_date"
    case endDate = "end_date"
    case name
    case currency
    case initialized
    case current
    case allocatedSpending = "allocated_spending"
    case allocatedSpendingCents = "allocated_spending_cents"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }
}
