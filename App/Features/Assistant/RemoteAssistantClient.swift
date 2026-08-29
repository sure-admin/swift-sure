import Foundation

protocol RemoteAssistantClient {
  func createChat() async throws -> UUID
  func sendMessage(_ content: String, chatID: UUID) async throws -> String
}
