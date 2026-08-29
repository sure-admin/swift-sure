import Foundation

struct AssistantMessage: Identifiable {
  var id: UUID
  var role: AssistantRole
  var content: String
  var date: Date
}
