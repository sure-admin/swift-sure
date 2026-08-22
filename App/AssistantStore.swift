import Foundation
import Observation

@MainActor
@Observable
final class AssistantStore {
  var messages = [
    AssistantMessage(
      role: .assistant,
      content: "Ask me anything about your money. I can explain spending, compare accounts, find recurring costs, and help you plan."
    )
  ]
  var draft = ""
  var isResponding = false
  var errorMessage: String?
  private var chatID: String?

  func send() async {
    let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !prompt.isEmpty, !isResponding else { return }
    draft = ""
    messages.append(AssistantMessage(role: .user, content: prompt))
    isResponding = true
    errorMessage = nil

    let connection = SureConnection.shared
    guard connection.isConfigured else {
      errorMessage = "Connect your Sure API key in Connection Settings before sending a message."
      isResponding = false
      return
    }

    do {
      let client = SureAPIClient(connection: connection)
      let identifier: String
      if let chatID {
        identifier = chatID
      } else {
        identifier = try await client.createChat()
      }
      chatID = identifier
      let response = try await client.sendMessage(prompt, chatID: identifier)
      messages.append(AssistantMessage(role: .assistant, content: response))
    } catch {
      errorMessage = error.localizedDescription
    }
    isResponding = false
  }

}
