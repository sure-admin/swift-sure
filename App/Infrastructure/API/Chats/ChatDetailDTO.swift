import Foundation

struct ChatDetailDTO: Decodable {
  var id: UUID
  var title: String
  var error: String?
  var createdAt: Date
  var updatedAt: Date
  var messages: [MessageDTO]
  var pagination: PaginationDTO?

  enum CodingKeys: String, CodingKey {
    case id
    case title
    case error
    case createdAt = "created_at"
    case updatedAt = "updated_at"
    case messages
    case pagination
  }

  struct MessageDTO: Decodable {
    var id: UUID
    var type: MessageType
    var role: Role
    var content: String
    var model: String?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
      case id
      case type
      case role
      case content
      case model
      case createdAt = "created_at"
      case updatedAt = "updated_at"
    }
  }

  enum MessageType: String, Decodable {
    case user = "user_message"
    case assistant = "assistant_message"
  }

  enum Role: String, Decodable {
    case user
    case assistant
  }
}
