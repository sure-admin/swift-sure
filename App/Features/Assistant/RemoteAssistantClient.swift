import Foundation

protocol RemoteAssistantClient {
  func fetchConversations() async throws -> [AssistantConversation]
  func fetchConversation(id: UUID) async throws -> AssistantConversationDetail
  func createChat(title: String) async throws -> UUID
  func sendMessage(_ content: String, chatID: UUID) async throws -> String
}
