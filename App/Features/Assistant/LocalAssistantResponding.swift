@MainActor
protocol LocalAssistantResponding {
  func respond(to prompt: String, conversation: [AssistantMessage]) async throws -> String
}
