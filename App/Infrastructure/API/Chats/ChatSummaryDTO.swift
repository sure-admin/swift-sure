import Foundation

struct ChatSummaryDTO: Decodable {
  var id: UUID
  var title: String
  var lastMessageAt: Date?
  var messageCount: Int
  var error: String?
  var createdAt: Date
  var updatedAt: Date

  enum CodingKeys: String, CodingKey {
    case id
    case title
    case lastMessageAt = "last_message_at"
    case messageCount = "message_count"
    case error
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }
}
