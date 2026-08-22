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
      messages.append(AssistantMessage(role: .assistant, content: localResponse(for: prompt)))
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

  private func localResponse(for prompt: String) -> String {
    let lowered = prompt.lowercased()
    if lowered.contains("spend") || lowered.contains("budget") {
      return "You’ve spent $4,982 this month—12% less than July. Dining is at 82% of its budget, while shopping is $36 over plan."
    }
    if lowered.contains("save") {
      return "Your current savings rate is 41%. Keeping that pace would add about $41,700 over the next 12 months before investment returns."
    }
    return "Connect your Sure API key to get an answer grounded in your live demo finances. For now, the sample dashboard shows net worth of $143,047 and $3,478 left in this month’s budget."
  }
}
