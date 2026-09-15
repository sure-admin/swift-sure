struct AssistantConversationDetail: Codable {
  var conversation: AssistantConversation
  var messages: [AssistantMessage]
}
