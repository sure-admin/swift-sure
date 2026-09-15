import Foundation

struct AssistantConversation: Codable, Equatable, Identifiable {
  var id: UUID
  var title: String
  var updatedAt: Date

  func abridgedTitle(limit: Int = 32) -> String {
    Self.abridgedTitle(title, limit: limit)
  }

  static func abridgedTitle(_ title: String, limit: Int) -> String {
    let normalized = title
      .split(whereSeparator: \Character.isWhitespace)
      .joined(separator: " ")
    let displayTitle = normalized.isEmpty ? "Untitled conversation" : normalized
    guard displayTitle.count > limit else { return displayTitle }
    return "\(displayTitle.prefix(max(1, limit - 1)))…"
  }
}
