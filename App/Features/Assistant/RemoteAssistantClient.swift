protocol RemoteAssistantClient {
  func createChat() async throws -> String
  func sendMessage(_ content: String, chatID: String) async throws -> String
}
