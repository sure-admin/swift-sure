import Foundation

struct InsightDTO: Decodable {
  var id: UUID
  var type: String
  var title: String
  var body: String
  var priority: InsightPriorityDTO
  var status: InsightStatusDTO
  var generatedAt: Date?

  enum CodingKeys: String, CodingKey {
    case id
    case type
    case title
    case body
    case priority
    case status
    case generatedAt = "generated_at"
  }
}
