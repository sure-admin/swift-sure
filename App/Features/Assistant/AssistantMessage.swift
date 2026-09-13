import Foundation

struct AssistantMessage: Codable, Identifiable {
  var id: UUID
  var role: AssistantRole
  var content: String
  var date: Date
}
