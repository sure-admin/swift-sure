import Foundation
import Observation

@MainActor
@Observable
final class AssistantStore {
  var messages: [AssistantMessage]
  var draft = ""
  var isResponding = false
  var errorMessage: String?
  private var chatID: String?

  init() {
    messages = [
      AssistantMessage(role: .assistant, content: Self.introduction)
    ]
    updateConnectionPrompts(hasVerifiedAPIKey: SureConnection.shared.hasVerifiedAPIKey)
  }

  func updateConnectionPrompts(hasVerifiedAPIKey: Bool) {
    messages.removeAll { $0.content == Self.appleCardPrompt }
    if hasVerifiedAPIKey {
      messages.insert(
        AssistantMessage(role: .assistant, content: Self.appleCardPrompt),
        at: min(1, messages.endIndex)
      )
    }
  }

  func send(to destination: AssistantDestination) async {
    let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !prompt.isEmpty, !isResponding else { return }
    let conversation = messages
    draft = ""
    messages.append(AssistantMessage(role: .user, content: prompt))
    isResponding = true
    errorMessage = nil

    do {
      let response: String
      switch destination {
      case .localModel:
        response = try await LocalAssistantService.respond(to: prompt, conversation: conversation)
      case .sureServer:
        response = try await sendToSure(prompt)
      }
      messages.append(AssistantMessage(role: .assistant, content: response))
    } catch {
      errorMessage = error.localizedDescription
    }
    isResponding = false
  }

  private func sendToSure(_ prompt: String) async throws -> String {
    let connection = SureConnection.shared
    guard connection.isConfigured else {
      throw SureAPIError.unauthorized
    }

    let client = SureAPIClient(connection: connection)
    let identifier: String
    if let chatID {
      identifier = chatID
    } else {
      identifier = try await client.createChat()
    }
    chatID = identifier
    return try await client.sendMessage(prompt, chatID: identifier)
  }

  private static let introduction = "Here you will be able to ask me anything about your money. I can explain spending, compare accounts, find recurring costs, and help you plan."
  private static let appleCardPrompt = "Want to sync your Apple Card spending with Sure?"
}
