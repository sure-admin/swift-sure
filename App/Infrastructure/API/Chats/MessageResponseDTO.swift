import Foundation

struct MessageResponseDTO: Decodable {
  var id: UUID
  var type: ChatDetailDTO.MessageType
  var role: ChatDetailDTO.Role
  var content: String
  var model: String?
  var createdAt: Date
  var updatedAt: Date
  var chatID: UUID
  var aiResponseStatus: AIResponseStatus?
  var aiResponseMessage: String?

  enum CodingKeys: String, CodingKey {
    case id
    case type
    case role
    case content
    case model
    case createdAt = "created_at"
    case updatedAt = "updated_at"
    case chatID = "chat_id"
    case aiResponseStatus = "ai_response_status"
    case aiResponseMessage = "ai_response_message"
  }

  enum AIResponseStatus: String, Decodable {
    case pending
    case complete
    case failed
  }
}
